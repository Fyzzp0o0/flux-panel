package panel

// ============================================================
// 面板 chain/limiter 管理（v3 适配版，策略与 service.go 一致：
// 改内存配置 → 写 gost.json → SIGHUP 热重载）
// ============================================================

import (
	"errors"
	"strings"

	"github.com/go-gost/x/config"
)

// ===== Chain 管理 =====

func createChain(req createChainRequest) error {
	name := strings.TrimSpace(req.Data.Name)
	if name == "" {
		return errors.New("chain name is required")
	}
	req.Data.Name = name

	cfg := config.Global()
	for _, exist := range cfg.Chains {
		if exist.Name == name {
			return errors.New("chain " + name + " already exists")
		}
	}
	sc := req.Data
	cfg.Chains = append(cfg.Chains, &sc)

	return saveAndReload()
}

func updateChain(req updateChainRequest) error {
	name := strings.TrimSpace(req.Chain)
	req.Data.Name = name

	cfg := config.Global()
	for i := range cfg.Chains {
		if cfg.Chains[i].Name == name {
			sc := req.Data
			cfg.Chains[i] = &sc
			return saveAndReload()
		}
	}
	return errors.New("chain " + name + " not found")
}

func deleteChain(req deleteChainRequest) error {
	name := strings.TrimSpace(req.Chain)

	cfg := config.Global()
	newChains := cfg.Chains[:0]
	found := false
	for _, c := range cfg.Chains {
		if c.Name == name {
			found = true
			continue
		}
		newChains = append(newChains, c)
	}
	cfg.Chains = newChains
	if !found {
		return errors.New("chain " + name + " not found")
	}
	return saveAndReload()
}

type createChainRequest struct {
	Data config.ChainConfig `json:"data"`
}

type updateChainRequest struct {
	Chain string             `json:"chain"`
	Data  config.ChainConfig `json:"data"`
}

type deleteChainRequest struct {
	Chain string `json:"chain"`
}

// ===== Limiter 管理（流量限速，v3 存 Limiters）=====

func createLimiter(req createLimiterRequest) error {
	name := strings.TrimSpace(req.Data.Name)
	if name == "" {
		return errors.New("limiter name is required")
	}
	req.Data.Name = name

	cfg := config.Global()
	for _, exist := range cfg.Limiters {
		if exist.Name == name {
			return errors.New("limiter " + name + " already exists")
		}
	}
	sc := req.Data
	cfg.Limiters = append(cfg.Limiters, &sc)

	return saveAndReload()
}

func updateLimiter(req updateLimiterRequest) error {
	name := strings.TrimSpace(req.Limiter)
	req.Data.Name = name

	cfg := config.Global()
	for i := range cfg.Limiters {
		if cfg.Limiters[i].Name == name {
			sc := req.Data
			cfg.Limiters[i] = &sc
			return saveAndReload()
		}
	}
	return errors.New("limiter " + name + " not found")
}

func deleteLimiter(req deleteLimiterRequest) error {
	name := strings.TrimSpace(req.Limiter)

	cfg := config.Global()
	newLimiters := cfg.Limiters[:0]
	found := false
	for _, l := range cfg.Limiters {
		if l.Name == name {
			found = true
			continue
		}
		newLimiters = append(newLimiters, l)
	}
	cfg.Limiters = newLimiters
	if !found {
		return errors.New("limiter " + name + " not found")
	}
	return saveAndReload()
}

type createLimiterRequest struct {
	Data config.LimiterConfig `json:"data"`
}

type updateLimiterRequest struct {
	Limiter string               `json:"limiter"`
	Data    config.LimiterConfig `json:"data"`
}

type deleteLimiterRequest struct {
	Limiter string `json:"limiter"`
}
