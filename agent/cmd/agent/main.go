// Claude Remote Control Agent — 运行在用户 macOS/Windows 上的守护进程
// 职责: 连接 Relay Server，接收任务，启动 Claude Code CLI 执行，实时回传日志和结果
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/claude-remote-control/agent/config"
	"github.com/claude-remote-control/agent/internal/executor"
	"github.com/claude-remote-control/agent/internal/result"
	"github.com/claude-remote-control/agent/internal/security"
	"github.com/claude-remote-control/agent/internal/streamer"
	"github.com/claude-remote-control/agent/internal/task"
	"github.com/claude-remote-control/agent/internal/ws"
)

func main() {
	configPath := flag.String("config", "agent-config.json", "配置文件路径")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.Println("===== Claude Remote Control Agent v1.0.0 =====")

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	log.Printf("配置: server=%s platform=%s device=%s", cfg.ServerURL, cfg.Platform, cfg.DeviceName)

	// 检查 claude CLI 是否可用
	claude := executor.New()
	if !claude.IsInstalled() {
		log.Fatal("claude CLI 未安装，请先安装: https://claude.com/download")
	}
	log.Printf("claude CLI 检测成功: %s", claude.Path())

	wsClient := ws.NewClient(cfg.ServerURL, cfg.Token, cfg.DeviceID)

	var (
		cancelMu  sync.Mutex
		cancelMap = make(map[string]context.CancelFunc)
	)

	taskReceiver := task.NewReceiver(func(params task.TaskParams) {
		handleTask(wsClient, claude, params, &cancelMu, cancelMap)
	})
	wsClient.OnTaskReceived = taskReceiver.Handle
	wsClient.OnCancelReceived = func(taskID string) {
		cancelMu.Lock()
		cancel, ok := cancelMap[taskID]
		if ok {
			delete(cancelMap, taskID)
			cancel()
			log.Printf("[main] 任务 %s 已被服务端取消", taskID)
		}
		cancelMu.Unlock()
	}

	// 追问继续回调
	taskReceiver.OnContinue = func(params task.TaskContinueParams) {
		handleContinue(wsClient, claude, params, &cancelMu, cancelMap)
	}
	wsClient.OnContinueReceived = taskReceiver.HandleContinue

	// 优雅退出
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		log.Println("收到退出信号，正在关闭...")
		cancelMu.Lock()
		for taskID, cancel := range cancelMap {
			log.Printf("[main] 取消运行中任务: %s", taskID)
			cancel()
		}
		cancelMu.Unlock()
		wsClient.Close()
		os.Exit(0)
	}()

	wsClient.Run()
}

// handleTask 处理收到的任务
func handleTask(wsClient *ws.Client, claude *executor.Claude, params task.TaskParams,
	cancelMu *sync.Mutex, cancelMap map[string]context.CancelFunc) {

	log.Printf("开始处理任务: %s", params.TaskID)

	// 安全检查
	safe, reason := security.Check(params.Prompt)
	if !safe {
		log.Printf("[security] 拒绝执行: %s", reason)
		ack := task.NewRejectedMessage(params.TaskID, reason)
		wsClient.Send(ack)
		return
	}

	// 发送 ACK 确认
	ack := task.NewAcceptedMessage(params.TaskID)
	wsClient.Send(ack)

	// 发送 task_started
	wsClient.Send(ws.Message{
		Type: "task_started",
		Payload: map[string]interface{}{
			"task_id": params.TaskID,
		},
	})

	// 初始化流式上传器和结果收集器
	logStreamer := streamer.New(wsClient, params.TaskID)
	resultCollector := result.NewCollector(wsClient, params.TaskID)

	onLine := func(line string, isStderr bool) {
		logStreamer.OnLine(line, isStderr)
		resultCollector.CollectLog(line)
	}

	// 创建带超时的上下文，支持外部取消
	timeout := time.Duration(params.TimeoutMinutes) * time.Minute
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cancelMu.Lock()
	cancelMap[params.TaskID] = cancel
	cancelMu.Unlock()
	defer func() {
		cancelMu.Lock()
		delete(cancelMap, params.TaskID)
		cancelMu.Unlock()
	}()

	// 执行 Claude Code
	execTask := executor.Task{
		TaskID:           params.TaskID,
		Prompt:           params.Prompt,
		WorkingDirectory: params.WorkingDirectory,
		PermissionMode:   params.PermissionMode,
	}

	execResult := claude.Execute(ctx, execTask, onLine)

	// 区分超时取消和失败
	if execResult.ExitCode != 0 || execResult.Error != nil {
		if ctx.Err() != nil {
			if ctx.Err() == context.DeadlineExceeded {
				execResult.Error = fmt.Errorf("任务执行超时 (%v)", timeout)
				execResult.ExitCode = -1
			} else if ctx.Err() == context.Canceled {
				// 被取消 — 不发送失败结果，只记录
				log.Printf("任务 %s 已取消", params.TaskID)
				return
			}
		}
	}

	// 发送最终结果（task_completed 或 task_failed）
	if err := resultCollector.Send(execResult); err != nil {
		log.Printf("发送最终结果失败: %v", err)
	}

	fmt.Printf("任务 %s 处理完成\n", params.TaskID)
}

// handleContinue 处理追问，在同一任务上下文中继续执行
func handleContinue(wsClient *ws.Client, claude *executor.Claude, params task.TaskContinueParams,
	cancelMu *sync.Mutex, cancelMap map[string]context.CancelFunc) {

	log.Printf("开始处理追问: %s", params.TaskID)

	// 安全检查
	safe, reason := security.Check(params.Prompt)
	if !safe {
		log.Printf("[security] 追问被拒绝: %s", reason)
		wsClient.Send(ws.Message{
			Type: "task_failed",
			Payload: map[string]interface{}{
				"task_id": params.TaskID,
				"error":   reason,
			},
		})
		return
	}

	// 发送 task_started（不发送 task_accepted，因为不是新任务）
	wsClient.Send(ws.Message{
		Type: "task_started",
		Payload: map[string]interface{}{
			"task_id": params.TaskID,
		},
	})

	// 初始化流式上传器和结果收集器
	logStreamer := streamer.New(wsClient, params.TaskID)
	resultCollector := result.NewCollector(wsClient, params.TaskID)

	onLine := func(line string, isStderr bool) {
		logStreamer.OnLine(line, isStderr)
		resultCollector.CollectLog(line)
	}

	// 创建新超时上下文，复用相同的 taskID（覆盖之前的 cancel func）
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	cancelMu.Lock()
	// 如果之前有同 taskID 的运行中任务，先取消旧的
	if oldCancel, ok := cancelMap[params.TaskID]; ok {
		oldCancel()
	}
	cancelMap[params.TaskID] = cancel
	cancelMu.Unlock()
	defer func() {
		cancelMu.Lock()
		delete(cancelMap, params.TaskID)
		cancelMu.Unlock()
	}()

	// 执行 Claude Code
	execTask := executor.Task{
		TaskID:           params.TaskID,
		Prompt:           params.Prompt,
		WorkingDirectory: params.WorkingDirectory,
	}

	execResult := claude.Execute(ctx, execTask, onLine)

	// 区分超时取消和失败
	if execResult.ExitCode != 0 || execResult.Error != nil {
		if ctx.Err() != nil {
			if ctx.Err() == context.DeadlineExceeded {
				execResult.Error = fmt.Errorf("追问执行超时 (30m)")
				execResult.ExitCode = -1
			} else if ctx.Err() == context.Canceled {
				log.Printf("追问 %s 已取消", params.TaskID)
				return
			}
		}
	}

	// 发送最终结果
	if err := resultCollector.Send(execResult); err != nil {
		log.Printf("发送追问结果失败: %v", err)
	}

	fmt.Printf("追问 %s 处理完成\n", params.TaskID)
}
