package panel

// ============================================================
// 面板流量统计 Observer（v3 内核集成）
//
// v0.x 时代在 fork 的 x/service 中给 handler 挂流量钩子；
// v3 内核使用上游原版 x，改用 v3 原生 observer 机制：
//   - 本包实现 core/observer.Observer 接口
//   - init() 时注册到 registry.ObserverRegistry()（名 panel-observer）
//   - v3 的 loader.Load 会清空 observer 注册表（配置驱动），
//     因此每次配置加载/命令处理后通过 EnsureObserverRegistered()
//     幂等恢复注册
//   - createServices/updateServices 时自动给服务注入
//     service.observer + handler.observer + enableStats metadata
//   - Observe 收到 StatsEvent 后计算增量流量 → GlobalTrafficManager
//     （每 5 秒批量上报到面板 /flow/upload）
// ============================================================

import (
	"context"
	"fmt"
	"sync"

	"github.com/go-gost/core/observer"
	"github.com/go-gost/x/observer/stats"
	"github.com/go-gost/x/registry"
)

const panelObserverName = "panel-observer"

// panelObserver 面板流量统计观察器
type panelObserver struct {
	mu      sync.Mutex
	lastIn  map[string]uint64 // 各服务上次上报的输入字节（用于计算增量）
	lastOut map[string]uint64 // 各服务上次上报的输出字节
}

// EnsureObserverRegistered 确保面板 observer 已注册（幂等）。
// v3 的 loader.Load 会清空 observer 注册表（配置驱动），因此每次
// 配置加载后都需要重新注册。
func EnsureObserverRegistered() {
	if registry.ObserverRegistry().IsRegistered(panelObserverName) {
		return
	}
	if err := registry.ObserverRegistry().Register(panelObserverName, &panelObserver{
		lastIn:  make(map[string]uint64),
		lastOut: make(map[string]uint64),
	}); err != nil {
		fmt.Printf("⚠️ panel-observer 注册失败: %v\n", err)
	}
}

// Observe 接收服务状态/统计事件
func (o *panelObserver) Observe(_ context.Context, events []observer.Event, _ ...observer.Option) error {
	for _, e := range events {
		if se, ok := e.(stats.StatsEvent); ok {
			o.mu.Lock()
			prevIn := o.lastIn[se.Service]
			prevOut := o.lastOut[se.Service]
			o.lastIn[se.Service] = se.InputBytes
			o.lastOut[se.Service] = se.OutputBytes
			o.mu.Unlock()

			// StatsEvent 的 InputBytes/OutputBytes 为累计值，计算增量后累加
			in := int64(0)
			out := int64(0)
			if se.InputBytes >= prevIn {
				in = int64(se.InputBytes - prevIn)
			}
			if se.OutputBytes >= prevOut {
				out = int64(se.OutputBytes - prevOut)
			}
			if in > 0 || out > 0 {
				GetGlobalTrafficManager().AddTraffic(se.Service, out, in)
			}
		}
	}
	return nil
}

func init() {
	// 首次注册（loader.Load 会在加载配置时清空，后续由 EnsureObserverRegistered 恢复）
	EnsureObserverRegistered()
}
