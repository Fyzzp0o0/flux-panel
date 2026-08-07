package panel

// ============================================================
// 面板服务管理（v3 适配版 v2）
// 策略：面板指令 → 通过 config.OnUpdate 修改内存配置(全局本体)
//      → 写 gost.json → 向自身发送 SIGHUP 触发 v3 原生热重载
// 注意：config.Global() 返回浅拷贝，append/替换必须走 OnUpdate
//      （在锁内直接操作 global 本体），否则修改不生效。
// pause 的服务暂存 paused_services.json，resume 时恢复
// ============================================================

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"syscall"

	"github.com/go-gost/x/config"
)

const gostConfigFile = "gost.json"
const pausedServicesFile = "paused_services.json"

// saveAndReload 保存配置并触发 SIGHUP 热重载
func saveAndReload() error {
	f, err := os.Create(gostConfigFile)
	if err != nil {
		return err
	}
	defer f.Close()

	if err := config.Global().Write(f, "json"); err != nil {
		return err
	}
	f.Sync()

	// 触发 v3 program.go 中注册的 SIGHUP 重载
	if err := syscall.Kill(os.Getpid(), syscall.SIGHUP); err != nil {
		return fmt.Errorf("trigger reload failed: %v", err)
	}
	return nil
}

func createServices(req createServicesRequest) error {
	if len(req.Data) == 0 {
		return errors.New("services list cannot be empty")
	}

	for _, serviceConfig := range req.Data {
		name := strings.TrimSpace(serviceConfig.Name)
		if name == "" {
			return errors.New("service name is required")
		}
		serviceConfig.Name = name

		// 自动注入面板流量统计 observer（service 级收 StatsEvent + handler 级 enableStats）
		if serviceConfig.Observer == "" {
			serviceConfig.Observer = panelObserverName
		}
		if serviceConfig.Handler != nil {
			if serviceConfig.Handler.Observer == "" {
				serviceConfig.Handler.Observer = panelObserverName
			}
		}
		// enableStats/observePeriod 为 service 级 metadata（v3 解析器读取 cfg.Metadata）
		if serviceConfig.Metadata == nil {
			serviceConfig.Metadata = make(map[string]any)
		}
		if _, ok := serviceConfig.Metadata["enableStats"]; !ok {
			serviceConfig.Metadata["enableStats"] = true
		}
		if _, ok := serviceConfig.Metadata["observePeriod"]; !ok {
			serviceConfig.Metadata["observePeriod"] = "5s"
		}

		err := config.OnUpdate(func(c *config.Config) error {
			// 查重（在锁内检查真实 global）
			for _, exist := range c.Services {
				if exist.Name == name {
					return errors.New("service " + name + " already exists")
				}
			}
			sc := serviceConfig
			c.Services = append(c.Services, &sc)
			return nil
		})
		if err != nil {
			return err
		}
	}

	return saveAndReload()
}

func updateServices(req updateServicesRequest) error {
	if len(req.Data) == 0 {
		return errors.New("services list cannot be empty")
	}

	for _, serviceConfig := range req.Data {
		name := strings.TrimSpace(serviceConfig.Name)
		if name == "" {
			return errors.New("service name is required")
		}
		serviceConfig.Name = name

		// 自动注入面板流量统计 observer（service 级收 StatsEvent + handler 级 enableStats）
		if serviceConfig.Observer == "" {
			serviceConfig.Observer = panelObserverName
		}
		if serviceConfig.Handler != nil {
			if serviceConfig.Handler.Observer == "" {
				serviceConfig.Handler.Observer = panelObserverName
			}
		}
		// enableStats/observePeriod 为 service 级 metadata（v3 解析器读取 cfg.Metadata）
		if serviceConfig.Metadata == nil {
			serviceConfig.Metadata = make(map[string]any)
		}
		if _, ok := serviceConfig.Metadata["enableStats"]; !ok {
			serviceConfig.Metadata["enableStats"] = true
		}
		if _, ok := serviceConfig.Metadata["observePeriod"]; !ok {
			serviceConfig.Metadata["observePeriod"] = "5s"
		}

		err := config.OnUpdate(func(c *config.Config) error {
			for i := range c.Services {
				if c.Services[i].Name == name {
					sc := serviceConfig
					c.Services[i] = &sc
					return nil
				}
			}
			return errors.New("service " + name + " not found")
		})
		if err != nil {
			return err
		}
	}

	return saveAndReload()
}

func deleteServices(req deleteServicesRequest) error {
	if len(req.Services) == 0 {
		return errors.New("services list cannot be empty")
	}

	for _, serviceName := range req.Services {
		name := strings.TrimSpace(serviceName)
		if name == "" {
			return errors.New("service name is required")
		}

		err := config.OnUpdate(func(c *config.Config) error {
			found := false
			newServices := c.Services[:0]
			for _, s := range c.Services {
				if s.Name == name {
					found = true
					continue
				}
				newServices = append(newServices, s)
			}
			c.Services = newServices
			if !found {
				return errors.New("service " + name + " not found")
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	return saveAndReload()
}

func pauseServices(req pauseServicesRequest) error {
	if len(req.Services) == 0 {
		return errors.New("services list cannot be empty")
	}

	// 在锁内筛选并移除，同时收集暂停的服务
	var paused []*config.ServiceConfig
	err := config.OnUpdate(func(c *config.Config) error {
		newServices := c.Services[:0]
		for _, s := range c.Services {
			needPause := false
			for _, serviceName := range req.Services {
				if s.Name == strings.TrimSpace(serviceName) {
					needPause = true
					break
				}
			}
			if needPause {
				paused = append(paused, s)
			} else {
				newServices = append(newServices, s)
			}
		}
		if len(paused) == 0 {
			return errors.New("no matching services found")
		}
		c.Services = newServices
		return nil
	})
	if err != nil {
		return err
	}

	// 合并已有暂停记录（去重）
	existing := loadPausedServices()
	merged := existing
	for _, p := range paused {
		dup := false
		for _, e := range merged {
			if e.Name == p.Name {
				dup = true
				break
			}
		}
		if !dup {
			merged = append(merged, p)
		}
	}
	savePausedServices(merged)

	return saveAndReload()
}

func resumeServices(req resumeServicesRequest) error {
	if len(req.Services) == 0 {
		return errors.New("services list cannot be empty")
	}

	paused := loadPausedServices()

	// 恢复指定服务（锁内追加）
	err := config.OnUpdate(func(c *config.Config) error {
		var remaining []*config.ServiceConfig
		restored := 0
		for _, p := range paused {
			resume := false
			for _, serviceName := range req.Services {
				if p.Name == strings.TrimSpace(serviceName) {
					resume = true
					break
				}
			}
			if resume {
				c.Services = append(c.Services, p)
				restored++
			} else {
				remaining = append(remaining, p)
			}
		}
		if restored == 0 {
			return errors.New("no matching paused services found")
		}
		savePausedServices(remaining)
		return nil
	})
	if err != nil {
		return err
	}

	return saveAndReload()
}

// loadPausedServices 读取暂停的服务记录
func loadPausedServices() []*config.ServiceConfig {
	data, err := os.ReadFile(pausedServicesFile)
	if err != nil {
		return nil
	}
	var list []*config.ServiceConfig
	if json.Unmarshal(data, &list) != nil {
		return nil
	}
	return list
}

// savePausedServices 保存暂停的服务记录
func savePausedServices(list []*config.ServiceConfig) {
	data, _ := json.Marshal(list)
	_ = os.WriteFile(pausedServicesFile, data, 0644)
}

// ===== 请求结构体（面板协议，与 v0.x 保持一致）=====

type createServicesRequest struct {
	Data []config.ServiceConfig `json:"data"`
}

type updateServicesRequest struct {
	Data []config.ServiceConfig `json:"data"`
}

type deleteServicesRequest struct {
	Services []string `json:"services"`
}

type pauseServicesRequest struct {
	Services []string `json:"services"`
}

type resumeServicesRequest struct {
	Services []string `json:"services"`
}
