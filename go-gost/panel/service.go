package panel

// ============================================================
// 面板服务管理（v3 适配版）
// 策略：面板指令 → 修改内存配置(config.Global) → 写 gost.json
//      → 向自身发送 SIGHUP 触发 v3 原生热重载（program.go reload）
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

	cfg := config.Global()
	for _, serviceConfig := range req.Data {
		name := strings.TrimSpace(serviceConfig.Name)
		if name == "" {
			return errors.New("service name is required")
		}
		serviceConfig.Name = name

		// 查重
		for _, exist := range cfg.Services {
			if exist.Name == name {
				return errors.New("service " + name + " already exists")
			}
		}
		sc := serviceConfig
		cfg.Services = append(cfg.Services, &sc)
	}

	return saveAndReload()
}

func updateServices(req updateServicesRequest) error {
	if len(req.Data) == 0 {
		return errors.New("services list cannot be empty")
	}

	cfg := config.Global()
	for _, serviceConfig := range req.Data {
		name := strings.TrimSpace(serviceConfig.Name)
		if name == "" {
			return errors.New("service name is required")
		}
		serviceConfig.Name = name

		found := false
		for i := range cfg.Services {
			if cfg.Services[i].Name == name {
				sc := serviceConfig
				cfg.Services[i] = &sc
				found = true
				break
			}
		}
		if !found {
			return errors.New("service " + name + " not found")
		}
	}

	return saveAndReload()
}

func deleteServices(req deleteServicesRequest) error {
	if len(req.Services) == 0 {
		return errors.New("services list cannot be empty")
	}

	cfg := config.Global()
	for _, serviceName := range req.Services {
		name := strings.TrimSpace(serviceName)
		if name == "" {
			return errors.New("service name is required")
		}

		found := false
		newServices := cfg.Services[:0]
		for _, s := range cfg.Services {
			if s.Name == name {
				found = true
				continue
			}
			newServices = append(newServices, s)
		}
		cfg.Services = newServices
		if !found {
			return errors.New("service " + name + " not found")
		}
	}

	return saveAndReload()
}

func pauseServices(req pauseServicesRequest) error {
	if len(req.Services) == 0 {
		return errors.New("services list cannot be empty")
	}

	cfg := config.Global()

	// 筛选需要暂停的服务
	var paused []*config.ServiceConfig
	newServices := cfg.Services[:0]
	for _, s := range cfg.Services {
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

	cfg.Services = newServices

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

	cfg := config.Global()
	paused := loadPausedServices()

	// 恢复指定服务
	var remaining []*config.ServiceConfig
	for _, p := range paused {
		resume := false
		for _, serviceName := range req.Services {
			if p.Name == strings.TrimSpace(serviceName) {
				resume = true
				break
			}
		}
		if resume {
			cfg.Services = append(cfg.Services, p)
		} else {
			remaining = append(remaining, p)
		}
	}

	savePausedServices(remaining)
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
