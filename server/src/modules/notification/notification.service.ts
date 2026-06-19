// 通知服务 — 任务完成/失败时触发推送（MVP 阶段仅记录日志）
import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);

  /** 任务完成通知 */
  async notifyTaskCompleted(userId: string, taskId: string, title: string): Promise<void> {
    this.logger.log(`[PUSH] 任务完成: user=${userId}, task=${taskId}, title=${title}`);
    // TODO: APNs 集成 — 调用 Apple Push Notification service 发送推送
  }

  /** 任务失败通知 */
  async notifyTaskFailed(userId: string, taskId: string, title: string, error: string): Promise<void> {
    this.logger.log(`[PUSH] 任务失败: user=${userId}, task=${taskId}, title=${title}, error=${error}`);
    // TODO: APNs 集成
  }

  /** 设备离线通知 */
  async notifyDeviceOffline(userId: string, deviceId: string, deviceName: string): Promise<void> {
    this.logger.log(`[PUSH] 设备离线: user=${userId}, device=${deviceId}, name=${deviceName}`);
    // TODO: APNs 集成
  }

  /** 设备上线通知 */
  async notifyDeviceOnline(userId: string, deviceId: string, deviceName: string): Promise<void> {
    this.logger.log(`[PUSH] 设备上线: user=${userId}, device=${deviceId}, name=${deviceName}`);
    // TODO: APNs 集成
  }
}
