package panel

// ===== 面板扩展启动/停止入口（v3 适配层）=====

var panelCfg *Config

// SetPanelConfig 设置面板连接配置
func SetPanelConfig(cfg *Config) {
	panelCfg = cfg
}

// StartPanelServices 启动面板上报服务（HTTP 流量上报 + WebSocket 实时监控）
func StartPanelServices() {
	if panelCfg == nil {
		return
	}
	// loader.Load 会清空 observer 注册表，这里恢复面板 observer
	EnsureObserverRegistered()
	// HTTP 流量上报（与 v0.x 行为一致）
	SetHTTPReportURL(panelCfg.Addr, panelCfg.Secret)
	// WebSocket 实时监控上报（内置断线重连）
	StartWebSocketReporterWithConfig(panelCfg.Addr, panelCfg.Secret, panelCfg.Http, panelCfg.Tls, panelCfg.Socks, "")
}

// StopPanelServices 停止面板上报服务
func StopPanelServices() {
	// WebSocket reporter 无独立 Stop（进程退出时连接自动关闭），
	// 这里停止全局流量管理器
	GetGlobalTrafficManager().Stop()
}
