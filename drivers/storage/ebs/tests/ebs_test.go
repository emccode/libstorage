// +build !libstorage_storage_driver libstorage_storage_driver_ebs

package ebs

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"

	log "github.com/Sirupsen/logrus"
	gofig "github.com/akutz/gofig/types"

	"github.com/stretchr/testify/assert"

	"github.com/codedellemc/libstorage/api/context"
	"github.com/codedellemc/libstorage/api/registry"
	"github.com/codedellemc/libstorage/api/server"
	apitests "github.com/codedellemc/libstorage/api/tests"
	"github.com/codedellemc/libstorage/api/types"
	"github.com/codedellemc/libstorage/api/utils"
	"github.com/codedellemc/libstorage/drivers/storage/ebs"
	ebsUtils "github.com/codedellemc/libstorage/drivers/storage/ebs/utils"
)

// Put contents of sample config.yml here
var (
	configYAMLec2 = []byte(`
libstorage:
  service: ec2
  integration:
    volume:
      operations:
        mount:
          preempt: true
ec2:
  region: us-west-2
  endpoint: ec2.us-west-2.amazonaws.com
  accessKey: %s
  secretKey: %s
`)

	configYAMLebs = []byte(`
libstorage:
  service: ebs
  integration:
    volume:
      operations:
        mount:
          preempt: true
ebs:
  region: us-west-2
  endpoint: ec2.us-west-2.amazonaws.com
  accessKey: %s
  secretKey: %s
`)
)

var volumeName string
var volumeName2 string

// Check environment vars to see whether or not to run this test
func skipTests() bool {
	travis, _ := strconv.ParseBool(os.Getenv("TRAVIS"))
	noTestEC2, _ := strconv.ParseBool(os.Getenv("TEST_SKIP_EC2"))
	noTestEBS, _ := strconv.ParseBool(os.Getenv("TEST_SKIP_EBS"))
	return travis || (noTestEC2 || noTestEBS)
}

// Set volume names to first part of UUID before the -
func init() {
	log.SetOutput(os.Stdout)
	log.SetLevel(log.DebugLevel)

	volumeName = os.Getenv("FIRST_VOLUME")
	if len(volumeName) == 0 {
		uuid, _ := types.NewUUID()
		uuids := strings.Split(uuid.String(), "-")
		volumeName = uuids[0]
	}
	volumeName2 = os.Getenv("SECOND_VOLUME")
	if len(volumeName2) == 0 {
		uuid, _ := types.NewUUID()
		uuids := strings.Split(uuid.String(), "-")
		volumeName2 = uuids[0]
	}

	// Build configuration based on provided environmet
	awsAccessKey := os.Getenv("AWS_ACCESSKEY")
	awsSecretKey := os.Getenv("AWS_SECRETKEY")

	configYAMLec2 = []byte(fmt.Sprintf(string(configYAMLec2[:]), awsAccessKey, awsSecretKey))
	configYAMLebs = []byte(fmt.Sprintf(string(configYAMLebs[:]), awsAccessKey, awsSecretKey))
}

func TestMain(m *testing.M) {
	server.CloseOnAbort()
	ec := m.Run()
	os.Exit(ec)
}

///////////////////////////////////////////////////////////////////////
/////////                    PUBLIC TESTS                     /////////
///////////////////////////////////////////////////////////////////////
// Test if backwards compatibility for "ec2" and "ebs" work in config
func TestConfig(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}
	tfEBS := func(config gofig.Config, client types.Client, t *testing.T) {
		assert.NotEqual(t, config.GetString("ebs.accessKey"), "")
		assert.Equal(t, config.GetString("ec2.accessKey"), "")
	}
	tfEC2 := func(config gofig.Config, client types.Client, t *testing.T) {
		assert.NotEqual(t, config.GetString("ec2.accessKey"), "")
		assert.Equal(t, config.GetString("ebs.accessKey"), "")
	}
	apitests.Run(t, "ec2", configYAMLebs, tfEBS)
	apitests.Run(t, "ec2", configYAMLec2, tfEC2)
	apitests.Run(t, ebs.Name, configYAMLebs, tfEBS)
	apitests.Run(t, ebs.Name, configYAMLec2, tfEC2)
}

// Check if InstanceID metadata is properly returned by executor
// and InstanceID.ID is filled out by InstanceInspect
func TestInstanceID(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	// create storage driver
	sd, err := registry.NewStorageDriver(ebs.Name)
	if err != nil {
		t.Fatal(err)
	}

	// initialize storage driver
	ctx := context.Background()
	if err := sd.Init(ctx, registry.NewConfig()); err != nil {
		t.Fatal(err)
	}

	// Get Instance ID metadata from executor
	iid, err := ebsUtils.InstanceID(ctx, ebs.Name)
	assert.NoError(t, err)
	if err != nil {
		t.Fatal(err)
	}

	// Fill in Instance ID's ID field with InstanceInspect
	ctx = ctx.WithValue(context.InstanceIDKey, iid)
	i, err := sd.InstanceInspect(ctx, utils.NewStore())
	if err != nil {
		t.Fatal(err)
	}

	iid = i.InstanceID

	// test resulting InstanceID
	apitests.Run(
		t, ebs.Name, nil,
		(&apitests.InstanceIDTest{
			Driver:   ebs.Name,
			Expected: iid,
		}).Test)
}

// Check if InstanceID metadata is properly returned by executor
// and InstanceID.ID is filled out by InstanceInspect
func TestInstanceIDEC2(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	// create storage driver
	sd, err := registry.NewStorageDriver("ebs")
	if err != nil {
		t.Fatal(err)
	}

	// initialize storage driver
	ctx := context.Background()
	if err := sd.Init(ctx, registry.NewConfig()); err != nil {
		t.Fatal(err)
	}

	// Get Instance ID metadata from executor
	iid, err := ebsUtils.InstanceID(ctx, ebs.NameEC2)
	assert.NoError(t, err)
	if err != nil {
		t.Fatal(err)
	}

	// Fill in Instance ID's ID field with InstanceInspect
	ctx = ctx.WithValue(context.InstanceIDKey, iid)
	i, err := sd.InstanceInspect(ctx, utils.NewStore())
	if err != nil {
		t.Fatal(err)
	}

	iid = i.InstanceID

	// test resulting InstanceID
	apitests.Run(
		t, ebs.NameEC2, nil,
		(&apitests.InstanceIDTest{
			Driver:   ebs.NameEC2,
			Expected: iid,
		}).Test)
}

// Test if Services are configured and returned properly from the client
func TestServices(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	tf := func(config gofig.Config, client types.Client, t *testing.T) {
		reply, err := client.API().Services(nil)
		assert.NoError(t, err)
		assert.Equal(t, len(reply), 1)

		_, ok := reply[ebs.Name]
		assert.True(t, ok)
	}
	tf2 := func(config gofig.Config, client types.Client, t *testing.T) {
		reply, err := client.API().Services(nil)
		assert.NoError(t, err)
		assert.Equal(t, len(reply), 1)

		_, ok := reply[ebs.NameEC2]
		assert.True(t, ok)
	}
	apitests.Run(t, ebs.Name, configYAMLec2, tf)
	apitests.Run(t, ebs.NameEC2, configYAMLec2, tf2)
}

// Test volume functionality from storage driver
func TestVolumeAttach(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	tf := func(config gofig.Config, client types.Client, t *testing.T) {
		vol := volumeCreate(t, client, volumeName,
			config.GetString("ec2.tag"))
		_ = volumeAttach(t, client, vol.ID)
		_ = volumeInspectAttached(t, client, vol.ID)
		_ = volumeInspectAvailableFail(t, client, vol.ID)
		_ = volumeDetach(t, client, vol.ID)
		_ = volumeInspectDetached(t, client, vol.ID)
		volumeRemove(t, client, vol.ID)
	}

	apitests.Run(t, ebs.Name, configYAMLebs, tf)
}

// Test volume functionality from storage driver
func TestVolumeCreateRemove(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	tf := func(config gofig.Config, client types.Client, t *testing.T) {
		vol := volumeCreate(t, client, volumeName,
			config.GetString("ec2.tag"))
		volumeRemove(t, client, vol.ID)
	}

	apitests.Run(t, ebs.Name, configYAMLebs, tf)
}

// Test volume functionality from storage driver
func TestEncryptedVolumeCreateRemove(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	tf := func(config gofig.Config, client types.Client, t *testing.T) {
		vol := volumeCreateEncrypted(t, client, volumeName,
			config.GetString("ec2.tag"))
		volumeRemove(t, client, vol.ID)
	}

	apitests.Run(t, ebs.Name, configYAMLebs, tf)
}

// Test volume functionality from storage driver
func TestVolumes(t *testing.T) {
	if skipTests() {
		t.SkipNow()
	}

	tf := func(config gofig.Config, client types.Client, t *testing.T) {
		_ = volumeCreate(t, client, volumeName,
			config.GetString("ec2.tag"))
		_ = volumeCreate(t, client, volumeName2,
			config.GetString("ec2.tag"))

		vol1 := volumeByName(t, client, volumeName,
			config.GetString("ec2.tag"))
		vol2 := volumeByName(t, client, volumeName2,
			config.GetString("ec2.tag"))

		volumeRemove(t, client, vol1.ID)
		volumeRemove(t, client, vol2.ID)
	}

	apitests.Run(t, ebs.Name, configYAMLebs, tf)
}

///////////////////////////////////////////////////////////////////////
/////////        PRIVATE TESTS FOR VOLUME FUNCTIONALITY       /////////
///////////////////////////////////////////////////////////////////////
// Test volume creation specifying size and volume name
func volumeCreate(
	t *testing.T,
	client types.Client,
	volumeName,
	tag string) *types.Volume {

	log.WithField("volumeName", volumeName).Info("creating volume")
	// Prepare request for storage driver call to create volume
	size := int64(1)

	opts := map[string]interface{}{
		"priority": 2,
		"owner":    "root@example.com",
	}

	volumeCreateRequest := &types.VolumeCreateRequest{
		Name: volumeName,
		Size: &size,
		Opts: opts,
	}

	// Send request and retrieve created libStorage types.Volume
	reply, err := client.API().VolumeCreate(
		nil, ebs.Name, volumeCreateRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed volumeCreate")
	}
	apitests.LogAsJSON(reply, t)

	// Check if name and size are same
	assert.Equal(t, volumeName, reply.Name)
	assert.Equal(t, size, reply.Size)
	return reply
}

// Test volume creation specifying size, volume name, and encryption
func volumeCreateEncrypted(
	t *testing.T,
	client types.Client,
	volumeName,
	tag string) *types.Volume {

	log.WithField("volumeName", volumeName).Info(
		"creating encrypted volume")
	// Prepare request for storage driver call to create volume
	size := int64(2)
	encrypted := true

	opts := map[string]interface{}{
		"priority": 2,
		"owner":    "root@example.com",
	}

	volumeCreateRequest := &types.VolumeCreateRequest{
		Name:      volumeName,
		Size:      &size,
		Encrypted: &encrypted,
		Opts:      opts,
	}

	// Send request and retrieve created libStorage types.Volume
	reply, err := client.API().VolumeCreate(
		nil, ebs.Name, volumeCreateRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed volumeCreate")
	}
	apitests.LogAsJSON(reply, t)

	// Check if name and size are same, and volume is encrypted
	assert.Equal(t, volumeName, reply.Name)
	assert.Equal(t, size, reply.Size)
	assert.Equal(t, encrypted, reply.Encrypted)
	return reply
}

// Test volume retrieval by volume name using Volumes, which retrieves all
// volumes from the storage driver without filtering, and filters the volumes
// externally.
func volumeByName(
	t *testing.T,
	client types.Client,
	volumeName,
	tag string) *types.Volume {

	log.WithField("volumeName", volumeName).Info("get volume by ebs.Name")
	// Retrieve all volumes
	vols, err := client.API().Volumes(nil, types.VolAttFalse)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
	}

	// Filter volumes to those under the ec2 service,
	// and find a volume matching inputted volume name
	assert.Contains(t, vols, ebs.Name)
	for _, vol := range vols[ebs.Name] {
		if vol.Name == volumeName {
			return vol
		}
	}
	// No matching volumes found
	t.FailNow()
	t.Error("failed volumeByName")
	return nil
}

// Test volume retrieval by volume ID using Volumes, which retrieves all
// volumes from the storage driver without filtering, and filters the volumes
// externally. Contrast with volumeInspect, which directly retrieves matching
// volumes from the storage driver.
func volumeByID(
	t *testing.T,
	client types.Client,
	volumeID string) *types.Volume {

	log.WithField("volumeID", volumeID).Info(
		"get volume by ebs.Name using ID")
	// Retrieve all volumes
	vols, err := client.API().Volumes(nil, types.VolAttFalse)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
	}
	// Filter volumes to those under the ec2 service,
	// and find a volume matching inputted volume ID
	assert.Contains(t, vols, ebs.Name)
	for _, vol := range vols[ebs.Name] {
		if vol.ID == volumeID {
			return vol
		}
	}
	// No matching volumes found
	t.FailNow()
	t.Error("failed volumeByID")
	return nil
}

// Test volume removal by volume ID
func volumeRemove(t *testing.T, client types.Client, volumeID string) {
	log.WithField("volumeID", volumeID).Info("removing volume")
	err := client.API().VolumeRemove(
		nil, ebs.Name, volumeID, false)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed volumeRemove")
		t.FailNow()
	}
}

// Test volume attachment by volume ID
func volumeAttach(
	t *testing.T, client types.Client, volumeID string) *types.Volume {
	log.WithField("volumeID", volumeID).Info("attaching volume")
	// Get next device name from executor
	nextDevice, err := client.Executor().NextDevice(
		context.Background().WithValue(context.ServiceKey, ebs.Name),
		utils.NewStore())
	assert.NoError(t, err)
	if err != nil {
		t.Error("error getting next device name from executor")
		t.FailNow()
	}

	reply, token, err := client.API().VolumeAttach(
		nil, ebs.Name, volumeID, &types.VolumeAttachRequest{
			NextDeviceName: &nextDevice,
		})

	assert.NoError(t, err)
	if err != nil {
		t.Error("failed volumeAttach")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	assert.NotEqual(t, token, "")

	return reply
}

// Test volume retrieval by volume ID using VolumeInspect, which directly
// retrieves matching volumes from the storage driver. Contrast with
// volumeByID, which uses Volumes to retrieve all volumes from the storage
// driver without filtering, and filters the volumes externally.
func volumeInspect(
	t *testing.T, client types.Client, volumeID string) *types.Volume {
	log.WithField("volumeID", volumeID).Info("inspecting volume")
	reply, err := client.API().VolumeInspect(
		nil, ebs.Name, volumeID, types.VolAttFalse)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed volumeInspect")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	return reply
}

// Test if volume is attached, its Attachments field should be populated
func volumeInspectAttached(
	t *testing.T, client types.Client, volumeID string) *types.Volume {
	log.WithField("volumeID", volumeID).Info("inspecting volume")
	reply, err := client.API().VolumeInspect(
		nil, ebs.Name, volumeID,
		types.VolAttReqTrue)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed volumeInspectAttached")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	assert.Len(t, reply.Attachments, 1)
	return reply
}

// Test if volume is detached, its Attachments field should not be populated
func volumeInspectDetached(
	t *testing.T, client types.Client, volumeID string) *types.Volume {
	log.WithField("volumeID", volumeID).Info("inspecting volume")
	reply, err := client.API().VolumeInspect(
		nil, ebs.Name, volumeID,
		types.VolAttReq)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed volumeInspectDetached")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	assert.Len(t, reply.Attachments, 0)
	return reply
}

// Test if volume is attached, but VolumeInspect is called to only request
// unattached volumes.
func volumeInspectAvailableFail(
	t *testing.T, client types.Client, volumeID string) *types.Volume {

	log.WithField("volumeID", volumeID).Info("inspecting volume")
	reply, err := client.API().VolumeInspect(nil, ebs.Name, volumeID,
		types.VolAttReqOnlyUnattachedVols)
	assert.Error(t, err)
	assert.Equal(t, "resource not found", err.Error())

	apitests.LogAsJSON(reply, t)
	return reply
}

// Test detaching volume by volume ID
func volumeDetach(
	t *testing.T, client types.Client, volumeID string) *types.Volume {
	log.WithField("volumeID", volumeID).Info("detaching volume")
	reply, err := client.API().VolumeDetach(
		nil, ebs.Name, volumeID, &types.VolumeDetachRequest{})
	assert.NoError(t, err)
	if err != nil {
		t.Error("failed volumeDetach")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	assert.Len(t, reply.Attachments, 0)
	return reply
}

///////////////////////////////////////////////////////////////////////
/////////       PRIVATE TESTS FOR SNAPSHOT FUNCTIONALITY      /////////
///////////////////////////////////////////////////////////////////////
// TODO Snapshots are not implemented yet
/*
// Test retrieving snapshot by snapshot ID
func snapshotInspect(
	t *testing.T, client types.Client, snapshotID string) *types.Snapshot {
	log.WithField("snapshotID", snapshotID).Info("inspecting snapshot")
	reply, err := client.API().SnapshotInspect(nil, ebs.Name, snapshotID)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed snapshotInspect")
		t.FailNow()
	}
	apitests.LogAsJSON(reply, t)
	return reply
}

// Test snapshot retrieval by snapshot name using Snapshots, which retrieves all snapshots
// from the storage driver without filtering, and filters the snapshots externally.
func snapshotByName(
	t *testing.T, client types.Client, snapshotName string) *types.Snapshot {
	log.WithField("snapshotName", snapshotName).Info("get snapshot by ebs.Name")
	// Retrieve all snapshots
	snapshots, err := client.API().Snapshots(nil)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
	}
	// Filter snapshots to those under the ec2 service,
	// and find a snapshot matching inputted snapshot name
	assert.Contains(t, snapshots, ebs.Name)
	for _, vol := range snapshots[ebs.Name] {
		if vol.Name == snapshotName {
			return vol
		}
	}
	// No matching snapshots found
	t.FailNow()
	t.Error("failed snapshotByName")
	return nil
}

// Test snapshot creation from existing volume, specifying volume ID of volume
// to copy, and snapshot name of snapshot to create
func volumeSnapshot(
	t *testing.T, client types.Client,
	volumeID, snapshotName string) *types.Snapshot {
	log.WithField("snapshotName", snapshotName).Info("creating snapshot")

	// Prepare request for storage driver call to create snapshot
		opts := map[string]interface{}{
			"priority": 2,
			"owner":    "root@example.com",
		}

	volumeSnapshotRequest := &types.VolumeSnapshotRequest{
		SnapshotName: snapshotName,
		//	Opts: opts,
	}

	// Send request and retrieve created libStorage types.Snapshot
	reply, err := client.API().VolumeSnapshot(nil, ebs.Name,
		volumeID, volumeSnapshotRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed volumeSnapshot")
	}
	apitests.LogAsJSON(reply, t)

	// Check if snapshot name and volume ID are same
	assert.Equal(t, snapshotName, reply.Name)
	assert.Equal(t, volumeID, reply.VolumeID)
	return reply
}

// Test copying snapshot from existing snapshot
func snapshotCopy(
	t *testing.T, client types.Client,
	snapshotID, snapshotName, destinationID string) *types.Snapshot {
	log.WithField("snapshotName", snapshotName).Info("copying snapshot")

	// Prepare request for storage driver call to copy snapshot
	snapshotCopyRequest := &types.SnapshotCopyRequest{
		SnapshotName: snapshotName,
		//DestinationID: destinationID,
		//	Opts: opts,
	}

	// Send request and retrieve created libStorage types.Snapshot
	reply, err := client.API().SnapshotCopy(nil, ebs.Name,
		snapshotID, snapshotCopyRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed snapshotCopy")
	}
	apitests.LogAsJSON(reply, t)

	// Check if snapshot name is same
	assert.Equal(t, snapshotName, reply.Name)
	return reply
}

// Test snapshot removal by snapshot ID
func snapshotRemove(t *testing.T, client types.Client, snapshotID string) {
	log.WithField("snapshotID", snapshotID).Info("removing snapshot")
	err := client.API().SnapshotRemove(
		nil, ebs.Name, snapshotID)
	assert.NoError(t, err)

	if err != nil {
		t.Error("failed snapshotRemove")
		t.FailNow()
	}
}

// Test volume creation from existing snapshot
func volumeCreateFromSnapshot(
	t *testing.T, client types.Client,
	snapshotID, volumeName string) *types.Volume {
	// Prepare request for storage driver call to create volume from snapshot
	fields := map[string]interface{}{
		"snapshotID": snapshotID,
		"volumeName": volumeName,
	}
	log.WithFields(fields).Info("creating volume from snapshot")
	size := int64(8)

	opts := map[string]interface{}{
		"priority": 2,
		"owner":    "root@example.com",
	}

	volumeCreateRequest := &types.VolumeCreateRequest{
		Name: volumeName,
		Size: &size,
		Opts: opts,
	}

	// Send request and retrieve created libStorage types.Volume
	reply, err := client.API().VolumeCreateFromSnapshot(nil,
		ebs.Name, snapshotID, volumeCreateRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed volumeCreateFromSnapshot")
	}
	apitests.LogAsJSON(reply, t)

	// Check if volume name, size, and opts are the same
	assert.Equal(t, volumeName, reply.Name)
	assert.Equal(t, size, reply.Size)
	assert.Equal(t, opts["priority"], 2)
	assert.Equal(t, opts["owner"], "root@example.com")

	return reply
}

// Test copying volume from existing volume, using volume ID of the volume
// to copy, and the desired volume name of the resulting volume copy.
func volumeCopy(
	t *testing.T, client types.Client,
	volumeID, volumeName string) *types.Volume {
	// Prepare request for storage driver call to copy volume
	fields := map[string]interface{}{
		"volumeID":   volumeID,
		"volumeName": volumeName,
	}
	log.WithFields(fields).Info("copying volume")

	opts := map[string]interface{}{
		"priority": 2,
		"owner":    "root@example.com",
	}

	volumeCopyRequest := &types.VolumeCopyRequest{
		VolumeName: volumeName,
		//Opts: opts,
	}

	// Send request and retrieve created libStorage types.Volume
	reply, err := client.API().VolumeCopy(nil,
		ebs.Name, volumeID, volumeCopyRequest)
	assert.NoError(t, err)
	if err != nil {
		t.FailNow()
		t.Error("failed volumeCopy")
	}
	apitests.LogAsJSON(reply, t)

	// Check if inputted volume name is the same as the created volume's
	assert.Equal(t, volumeName, reply.Name)

	return reply
}
*/
