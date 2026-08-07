package panel

// ============================================================
// 面板 chain/limiter 管理（v3 适配版 v2）
// 策略与 service.go 一致：config.OnUpdate 修改全局本体 →
// 写 gost.json → SIGHUP 热重载
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

	err := config.OnUpdate(func(c *config.Config) error {
		for _, exist := range c.Chains {
			if exist.Name == name {
				return errors.New("chain " + name + " already exists")
			}
		}
		sc := req.Data
		c.Chains = append(c.Chains, &sc)
		return nil
	})
	if err != nil {
		return err
	}

	return saveAndReload()
}

func updateChain(req updateChainRequest) error {
	name := strings.TrimSpace(req.Chain)
	req.Data.Name = name

	err := config.OnUpdate(func(c *config.Config) error {
		for i := range c.Chains {
			if c.Chains[i].Name == name {
				sc := req.Data
				c.Chains[i] = &sc
				return nil
			}
		}
		return errors.New("chain " + name + " not found")
	})
	if err != nil {
		return err
	}

	return saveAndReload()
}

func deleteChain(req deleteChainRequest) error {
	name := strings.TrimSpace(req.Chain)

	err := config.OnUpdate(func(c *config.Config) error {
		newChains := c.Chains[:0]
		found := false
		for _, ch := range c.Chains {
			if ch.Name == name {
				found = true
				continue
			}
			newChains = append(newChains, ch)
		}
		c.Chains = newChains
		if !found {
			return errors.New("chain " + name + " not found")
		}
		return nil
	})
	if err != nil {
		return err
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

	err := config.OnUpdate(func(c *config.Config) error {
		for _, exist := range c.Limiters {
			if exist.Name == name {
				return errors.New("limiter " + name + " already exists")
			}
		}
		sc := req.Data
		c.Limiters = append(c.Limiters, &sc)
		return nil
	})
	if err != nil {
		return err
	}

	return saveAndReload()
}

func updateLimiter(req updateLimiterRequest) error {
	name := strings.TrimSpace(req.Limiter)
	req.Data.Name = name

	err := config.OnUpdate(func(c *config.Config) error {
		for i := range c.Limiters {
			if c.Limiters[i].Name == name {
				sc := req.Data
				c.Limiters[i] = &sc
				return nil
			}
		}
		return errors.New("limiter " + name + " not found")
	})
	if err != nil {
		return err
	}

	return saveAndReload()
}

func deleteLimiter(req deleteLimiterRequest) error {
	name := strings.TrimSpace(req.Limiter)

	err := config.OnUpdate(func(c *config.Config) error {
		newLimiters := c.Limiters[:0]
		found := false
		for _, l := range c.Limiters {
			if l.Name == name {
				found = true
				continue
			}
			newLimiters = append(newLimiters, l)
		}
		c.Limiters = newLimiters
		if !found {
			return errors.New("limiter " + name + " not found")
		}
		return nil
	})
	if err != nil {
		return err
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
