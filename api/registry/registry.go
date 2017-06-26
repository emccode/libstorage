// Package registry is the central hub for Drivers and other types that
// follow the init-time registration.
package registry

import (
	"fmt"
	"strings"
	"sync"

	gofig "github.com/akutz/gofig/types"
	"github.com/akutz/goof"

	"github.com/codedellemc/libstorage/api/types"
	apitypesV1 "github.com/codedellemc/libstorage/api/types/v1"
)

var (
	modTypeCtors    = map[string]func() interface{}{}
	modTypeCtorsRWL = &sync.RWMutex{}

	storExecsCtors    = map[string]types.NewStorageExecutor{}
	storExecsCtorsRWL = &sync.RWMutex{}

	storDriverCtors    = map[string]types.NewStorageDriver{}
	storDriverCtorsRWL = &sync.RWMutex{}

	osDriverCtors    = map[string]types.NewOSDriver{}
	osDriverCtorsRWL = &sync.RWMutex{}

	intDriverCtors    = map[string]types.NewIntegrationDriver{}
	intDriverCtorsRWL = &sync.RWMutex{}

	cfgRegs    = []*cregW{}
	cfgRegsRWL = &sync.RWMutex{}

	routers    = []types.Router{}
	routersRWL = &sync.RWMutex{}
)

type cregW struct {
	name string
	creg types.NewConfigReg
}

// RegisterConfigReg registers a new configuration registration request.
func RegisterConfigReg(name string, f types.NewConfigReg) {
	cfgRegsRWL.Lock()
	defer cfgRegsRWL.Unlock()
	cfgRegs = append(cfgRegs, &cregW{name, f})
}

// RegisterModType registers a type from a plug-in mod.
func RegisterModType(name string, ctor func() interface{}) {
	modTypeCtorsRWL.Lock()
	defer modTypeCtorsRWL.Unlock()
	modTypeCtors[strings.ToLower(name)] = ctor
}

// RegisterRouter registers a Router.
func RegisterRouter(router types.Router) {
	routersRWL.Lock()
	defer routersRWL.Unlock()
	routers = append(routers, router)
}

// RegisterStorageExecutor registers a StorageExecutor.
func RegisterStorageExecutor(name string, ctor types.NewStorageExecutor) {
	storExecsCtorsRWL.Lock()
	defer storExecsCtorsRWL.Unlock()
	storExecsCtors[strings.ToLower(name)] = ctor
}

// RegisterStorageDriver registers a StorageDriver.
func RegisterStorageDriver(
	name string, ctor types.NewStorageDriver) {
	storDriverCtorsRWL.Lock()
	defer storDriverCtorsRWL.Unlock()
	storDriverCtors[strings.ToLower(name)] = ctor
}

// RegisterOSDriver registers a OSDriver.
func RegisterOSDriver(name string, ctor types.NewOSDriver) {
	osDriverCtorsRWL.Lock()
	defer osDriverCtorsRWL.Unlock()
	osDriverCtors[strings.ToLower(name)] = ctor
}

// RegisterIntegrationDriver registers a IntegrationDriver.
func RegisterIntegrationDriver(name string, ctor types.NewIntegrationDriver) {
	intDriverCtorsRWL.Lock()
	defer intDriverCtorsRWL.Unlock()
	intDriverCtors[strings.ToLower(name)] = ctor
}

// NewModType returns a new instance of the specified module type.
func NewModType(name string) (apitypesV1.Driver, error) {

	var ok bool
	var ctor func() interface{}

	func() {
		modTypeCtorsRWL.RLock()
		defer modTypeCtorsRWL.RUnlock()
		ctor, ok = modTypeCtors[name]
	}()

	if !ok {
		return nil, goof.WithField("modType", name, "invalid type name")
	}

	d, ok := ctor().(apitypesV1.Driver)
	if !ok {
		return nil, goof.WithField(
			"modType", fmt.Sprintf("%T", d), "invalid type")
	}

	return d, nil
}

// NewStorageExecutor returns a new instance of the executor specified by the
// executor name.
func NewStorageExecutor(name string) (types.StorageExecutor, error) {

	var ok bool
	var ctor types.NewStorageExecutor

	func() {
		storExecsCtorsRWL.RLock()
		defer storExecsCtorsRWL.RUnlock()
		ctor, ok = storExecsCtors[strings.ToLower(name)]
	}()

	if !ok {
		return nil, goof.WithField("executor", name, "invalid executor name")
	}

	return ctor(), nil
}

// NewStorageDriver returns a new instance of the driver specified by the
// driver name.
func NewStorageDriver(name string) (types.StorageDriver, error) {

	var ok bool
	var ctor types.NewStorageDriver

	func() {
		storDriverCtorsRWL.RLock()
		defer storDriverCtorsRWL.RUnlock()
		ctor, ok = storDriverCtors[strings.ToLower(name)]
	}()

	if !ok {
		return nil, goof.WithField("driver", name, "invalid driver name")
	}

	return ctor(), nil
}

// NewOSDriver returns a new instance of the driver specified by the
// driver name.
func NewOSDriver(name string) (types.OSDriver, error) {

	var ok bool
	var ctor types.NewOSDriver

	func() {
		osDriverCtorsRWL.RLock()
		defer osDriverCtorsRWL.RUnlock()
		ctor, ok = osDriverCtors[strings.ToLower(name)]
	}()

	if !ok {
		return nil, goof.WithField("driver", name, "invalid driver name")
	}

	return NewOSDriverManager(ctor()), nil
}

// NewIntegrationDriver returns a new instance of the driver specified by the
// driver name.
func NewIntegrationDriver(name string) (types.IntegrationDriver, error) {

	var ok bool
	var ctor types.NewIntegrationDriver

	func() {
		intDriverCtorsRWL.RLock()
		defer intDriverCtorsRWL.RUnlock()
		ctor, ok = intDriverCtors[strings.ToLower(name)]
	}()

	if !ok {
		return nil, goof.WithField("driver", name, "invalid driver name")
	}

	return NewIntegrationDriverManager(ctor()), nil
}

// ConfigRegs returns a channel on which all registered configuration
// registrations are returned.
func ConfigRegs(ctx types.Context) <-chan gofig.ConfigRegistration {
	c := make(chan gofig.ConfigRegistration)
	go func() {
		cfgRegsRWL.RLock()
		defer cfgRegsRWL.RUnlock()
		for _, cr := range cfgRegs {
			r := NewConfigReg(cr.name)
			cr.creg(ctx, r)
			c <- r
		}
		close(c)
	}()
	return c
}

// ModTypes returns a channel on which new instances of all registered
// module types.
func ModTypes() <-chan apitypesV1.Driver {
	c := make(chan apitypesV1.Driver)
	go func() {
		modTypeCtorsRWL.RLock()
		defer modTypeCtorsRWL.RUnlock()
		for _, ctor := range modTypeCtors {
			if d, ok := ctor().(apitypesV1.Driver); ok {
				c <- d
			}
		}
		close(c)
	}()
	return c
}

// StorageExecutors returns a channel on which new instances of all registered
// storage executors can be received.
func StorageExecutors() <-chan types.StorageExecutor {
	c := make(chan types.StorageExecutor)
	go func() {
		storExecsCtorsRWL.RLock()
		defer storExecsCtorsRWL.RUnlock()
		for _, ctor := range storExecsCtors {
			c <- ctor()
		}
		close(c)
	}()
	return c
}

// StorageDrivers returns a channel on which new instances of all
// registered remote storage drivers can be received.
func StorageDrivers() <-chan types.StorageDriver {
	c := make(chan types.StorageDriver)
	go func() {
		storDriverCtorsRWL.RLock()
		defer storDriverCtorsRWL.RUnlock()
		for _, ctor := range storDriverCtors {
			c <- ctor()
		}
		close(c)
	}()
	return c
}

// OSDrivers returns a channel on which new instances of all registered
// OS drivers can be received.
func OSDrivers() <-chan types.OSDriver {
	c := make(chan types.OSDriver)
	go func() {
		osDriverCtorsRWL.RLock()
		defer osDriverCtorsRWL.RUnlock()
		for _, ctor := range osDriverCtors {
			c <- ctor()
		}
		close(c)
	}()
	return c
}

// IntegrationDrivers returns a channel on which new instances of all registered
// integration drivers can be received.
func IntegrationDrivers() <-chan types.IntegrationDriver {
	c := make(chan types.IntegrationDriver)
	go func() {
		intDriverCtorsRWL.RLock()
		defer intDriverCtorsRWL.RUnlock()
		for _, ctor := range intDriverCtors {
			c <- ctor()
		}
		close(c)
	}()
	return c
}

// Routers returns a channel on which new instances of all registered routers
// can be received.
func Routers() <-chan types.Router {
	c := make(chan types.Router)
	go func() {
		routersRWL.RLock()
		defer routersRWL.RUnlock()
		for _, r := range routers {
			c <- r
		}
		close(c)
	}()
	return c
}
