package volume

import (
	"net/http"
	"strings"

	"github.com/akutz/gofig"
	"github.com/akutz/goof"

	"github.com/emccode/libstorage/api/server/httputils"
	"github.com/emccode/libstorage/api/server/services"
	"github.com/emccode/libstorage/api/types"
	"github.com/emccode/libstorage/api/types/context"
	"github.com/emccode/libstorage/api/types/drivers"
	apihttp "github.com/emccode/libstorage/api/types/http"
	apisvcs "github.com/emccode/libstorage/api/types/services"
	"github.com/emccode/libstorage/api/utils"
	"github.com/emccode/libstorage/api/utils/schema"
)

func newVolumesRoute(config gofig.Config, queryAttachments bool) *volumesRoute {
	return &volumesRoute{config, queryAttachments}
}

type volumesRoute struct {
	config           gofig.Config
	queryAttachments bool
}

//the filtering mechanism applies a simple match, you could do something like
//this future https://github.com/golang/appengine/blob/master/datastore/query.go
func applyFilter(obj *types.Volume, filters map[string][]string) bool {
	include := true
	for key, values := range filters {
		//fmt.Print("Filter Key: ", key, "\n")
		if len(obj.Fields[key]) == 0 {
			//fmt.Print("Key ", key, " not found\n")
			include = false
			break
		}
		if !include {
			//fmt.Print("Exiting early with no key found\n")
			break
		}

		found := false
		for _, value := range values {
			//fmt.Print("Filter Val: ", value, "\n")
			//omit adding to the slice if the key and value doesnt exist
			if strings.Compare(value, obj.Fields[key]) == 0 {
				//fmt.Print(value, " = ", obj.Fields[key], "\n")
				found = true //key exists and value exists in the map
				break
			}
		}
		if !found {
			//fmt.Print("Exiting early with no value found\n")
			include = false
			break
		}

		//fmt.Print("Found: ", found, "\n")
		include = include && found
		if !include {
			//fmt.Print("Exiting early with no key found\n")
			break
		}
	}

	return include
}

func (r *volumesRoute) volumes(ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	var attachments bool
	if r.queryAttachments {
		attachments = store.GetBool("attachments")
	}

	var (
		tasks   = map[string]*types.Task{}
		taskIDs []int
		reply   apihttp.ServiceVolumeMap = map[string]apihttp.VolumeMap{}
	)

	//filtering is done by query parameters on the URI
	var filters map[string][]string
	filters = req.URL.Query()

	for service := range services.StorageServices() {

		run := func(
			ctx context.Context,
			svc apisvcs.StorageService) (interface{}, error) {

			objs, err := svc.Driver().Volumes(
				ctx, &drivers.VolumesOpts{
					Attachments: attachments,
					Opts:        store,
				})
			if err != nil {
				return nil, err
			}

			objMap := map[string]*types.Volume{}
			for _, obj := range objs {
				if !applyFilter(obj, filters) {
					continue //object didnt not meet filter requirements
				}
				objMap[obj.ID] = obj
			}
			return objMap, nil
		}

		task := service.TaskExecute(ctx, run, schema.VolumeMapSchema)
		taskIDs = append(taskIDs, task.ID)
		tasks[service.Name()] = task
	}

	run := func(ctx context.Context) (interface{}, error) {

		services.TaskWaitAll(taskIDs...)

		for k, v := range tasks {
			if v.Error != nil {
				return nil, utils.NewBatchProcessErr(reply, v.Error)
			}

			objMap, ok := v.Result.(map[string]*types.Volume)
			if !ok {
				return nil, utils.NewBatchProcessErr(
					reply, goof.New("error casting to []*types.Volume"))
			}
			reply[k] = objMap
		}

		return reply, nil
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		services.TaskExecute(ctx, run, schema.ServiceVolumeMapSchema),
		http.StatusOK)
}

func (r *volumesRoute) volumesForService(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	//filtering is done by query parameters on the URI
	var filters map[string][]string
	filters = req.URL.Query()

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		var reply apihttp.VolumeMap = map[string]*types.Volume{}

		objs, err := svc.Driver().Volumes(
			ctx,
			&drivers.VolumesOpts{
				Attachments: store.GetBool("attachments"),
				Opts:        store,
			})
		if err != nil {
			return nil, err
		}

		for _, obj := range objs {
			if !applyFilter(obj, filters) {
				continue //object didnt not meet filter requirements
			}
			reply[obj.ID] = obj
		}
		return reply, nil
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeMapSchema),
		http.StatusOK)
}

func (r *router) volumeInspect(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return svc.Driver().VolumeInspect(
			ctx,
			store.GetString("volumeID"),
			&drivers.VolumeInspectOpts{
				Attachments: store.GetBool("attachments"),
				Opts:        store,
			})
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeSchema),
		http.StatusOK)
}

func (r *router) volumeCreate(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return svc.Driver().VolumeCreate(
			ctx,
			store.GetString("name"),
			&drivers.VolumeCreateOpts{
				AvailabilityZone: store.GetStringPtr("availabilityZone"),
				IOPS:             store.GetInt64Ptr("iops"),
				Size:             store.GetInt64Ptr("size"),
				Type:             store.GetStringPtr("type"),
				Opts:             store,
			})
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeSchema),
		http.StatusCreated)
}

func (r *router) volumeCopy(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return svc.Driver().VolumeCopy(
			ctx,
			store.GetString("volumeID"),
			store.GetString("volumeName"),
			store)
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeSchema),
		http.StatusCreated)
}

func (r *router) volumeSnapshot(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return svc.Driver().VolumeSnapshot(
			ctx,
			store.GetString("volumeID"),
			store.GetString("snapshotName"),
			store)
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.SnapshotSchema),
		http.StatusCreated)
}

func (r *router) volumeAttach(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return svc.Driver().VolumeAttach(
			ctx,
			store.GetString("volumeID"),
			&drivers.VolumeAttachByIDOpts{
				NextDevice: store.GetStringPtr("nextDeviceName"),
				Opts:       store,
			})
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeSchema),
		http.StatusOK)
}

func (r *router) volumeDetach(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return nil, svc.Driver().VolumeDetach(
			ctx,
			store.GetString("volumeID"),
			store)
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, nil),
		http.StatusResetContent)
}

func (r *router) volumeDetachAll(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	var (
		taskIDs []int
		tasks   = map[string]*types.Task{}
		opts    = &drivers.VolumesOpts{Opts: store}
	)

	var reply apihttp.ServiceVolumeMap = map[string]apihttp.VolumeMap{}

	for service := range services.StorageServices() {

		run := func(
			ctx context.Context,
			svc apisvcs.StorageService) (interface{}, error) {

			driver := svc.Driver()

			volumes, err := driver.Volumes(ctx, opts)
			if err != nil {
				return nil, err
			}

			var volumeMap apihttp.VolumeMap = map[string]*types.Volume{}
			defer func() {
				if len(volumeMap) > 0 {
					reply[service.Name()] = volumeMap
				}
			}()

			for _, volume := range volumes {
				err := driver.VolumeDetach(ctx, volume.ID, store)
				if err != nil {
					return nil, err
				}
				volumeMap[volume.ID] = volume
			}

			return nil, nil
		}

		task := service.TaskExecute(ctx, run, nil)
		taskIDs = append(taskIDs, task.ID)
		tasks[service.Name()] = task
	}

	run := func(ctx context.Context) (interface{}, error) {
		services.TaskWaitAll(taskIDs...)
		for _, v := range tasks {
			if v.Error != nil {
				return nil, utils.NewBatchProcessErr(reply, v.Error)
			}
		}
		return reply, nil
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		services.TaskExecute(ctx, run, schema.ServiceVolumeMapSchema),
		http.StatusResetContent)
}

func (r *router) volumeDetachAllForService(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	var reply apihttp.VolumeMap = map[string]*types.Volume{}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		driver := svc.Driver()

		volumes, err := driver.Volumes(ctx, &drivers.VolumesOpts{Opts: store})
		if err != nil {
			return nil, err
		}

		for _, volume := range volumes {
			err := driver.VolumeDetach(ctx, volume.ID, store)
			if err != nil {
				return nil, utils.NewBatchProcessErr(reply, err)
			}
			reply[volume.ID] = volume
		}

		return reply, nil
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, schema.VolumeMapSchema),
		http.StatusResetContent)
}

func (r *router) volumeRemove(
	ctx context.Context,
	w http.ResponseWriter,
	req *http.Request,
	store types.Store) error {

	service, err := httputils.GetService(ctx)
	if err != nil {
		return err
	}

	run := func(
		ctx context.Context,
		svc apisvcs.StorageService) (interface{}, error) {

		return nil, svc.Driver().VolumeRemove(
			ctx,
			store.GetString("volumeID"),
			store)
	}

	return httputils.WriteTask(
		ctx,
		w,
		store,
		service.TaskExecute(ctx, run, nil),
		http.StatusNoContent)
}
