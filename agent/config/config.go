// Package config 提供 Agent Service 的配置管理
//
// 安全提示: Token 字段存储 JWT 认证凭据。
// 生产环境中应避免明文存储，建议改用系统凭证存储：
//   - macOS: Keychain (security add-generic-password)
//   - Windows: Credential Manager (cmdkey)
//   - Linux: Secret Service API (secret-tool) 或文件权限 0600 保护
// 当前实现以 JSON 文件存储（仅 0600 权限），仅适用于开发/测试环境。
package config

import (
	"encoding/json"
	"os"
)

// Config Agent 完整配置
type Config struct {
	ServerURL   string `json:"server_url"`   // Relay Server WebSocket URL, e.g. "ws://192.168.1.100:3000/ws"
	Token       string `json:"token"`        // JWT 认证 token (生产环境应使用系统凭证存储，不要明文保存)
	DeviceName  string `json:"device_name"`   // 设备名称
	DeviceID    string `json:"device_id"`     // 设备唯一 ID（首次注册后由服务端返回）
	Platform    string `json:"platform"`      // 操作系统平台 "macos" | "windows"
	Version     string `json:"version"`       // Agent 版本号
}

// Load 从 JSON 配置文件加载配置，若文件不存在则返回默认配置
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return Default(), nil
		}
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

// Save 将配置保存到 JSON 文件
func (c *Config) Save(path string) error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

// Default 返回默认配置
func Default() *Config {
	hostname, _ := os.Hostname()
	platform := detectPlatform()
	return &Config{
		ServerURL:  "ws://localhost:3000/ws",
		DeviceName: hostname,
		Platform:   platform,
		Version:    "1.0.0",
	}
}

func detectPlatform() string {
	if _, err := os.Stat("/System/Library/CoreServices"); err == nil {
		return "macos"
	}
	return "windows"
}
