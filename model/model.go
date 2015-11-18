package model

// InstanceID identifies a host to a remote storage platform.
type InstanceID struct {
	// ID is the instance ID
	ID string `json:"id"`

	// Metadata is any extra information about the instance ID.
	Metadata interface{} `json:"metadata"`
}

// Instance provides information about a storage object.
type Instance struct {
	// The ID of the instance to which the object is connected.
	InstanceID *InstanceID `json:"instanceID"`

	// The name of the instance.
	Name string `json:"name"`

	// The name of the provider that owns the object.
	ProviderName string `json:"providerName"`

	// The region from which the object originates.
	Region string `json:"region"`
}

// MountInfo reveals information about a particular mounted filesystem. This
// struct is populated from the content in the /proc/<pid>/mountinfo file.
type MountInfo struct {
	// ID is a unique identifier of the mount (may be reused after umount).
	ID int `json:"id"`

	// Parent indicates the ID of the mount parent (or of self for the top of
	// the mount tree).
	Parent int `json:"parent"`

	// Major indicates one half of the device ID which identifies the device
	// class.
	Major int `json:"major"`

	// Minor indicates one half of the device ID which identifies a specific
	// instance of device.
	Minor int `json:"minor"`

	// Root of the mount within the filesystem.
	Root string `json:"root"`

	// MountPoint indicates the mount point relative to the process's root.
	MountPoint string `json:"mountPoint"`

	// Opts represents mount-specific options.
	Opts string `json:"opts"`

	// Optional represents optional fields.
	Optional string `json:"optional"`

	// FSType indicates the type of filesystem, such as EXT3.
	FSType string `json:"fsType"`

	// Source indicates filesystem specific information or "none".
	Source string `json:"source"`

	// VFSOpts represents per super block options.
	VFSOpts string `json:"vfsOpts"`
}

// BlockDevice provides information about a block-storage device.
type BlockDevice struct {
	// The name of the device.
	DeviceName string `json:"deviceName"`

	// The ID of the instance to which the device is connected.
	InstanceID *InstanceID `json:"instanceID"`

	// The name the device is known by in order to discover
	// locally.
	NetworkName string `json:"networkName"`

	// The name of the provider that owns the block device.
	ProviderName string `json:"providerName"`

	// The region from which the device originates.
	Region string `json:"region"`

	// The device status.
	Status string `json:"status"`

	// The ID of the volume for which the device is mounted.
	VolumeID string `json:"volumeID"`
}

// Snapshot provides information about a storage-layer snapshot.
type Snapshot struct {
	// A description of the snapshot.
	Description string `json:"description"`

	// The name of the snapshot.
	Name string `json:"name"`

	// The snapshot's ID.
	SnapshotID string `json:"snapshotID"`

	// The time at which the request to create the snapshot was submitted.
	StartTime string `json:"startTime"`

	// The status of the snapshot.
	Status string `json:"status"`

	// The ID of the volume to which the snapshot belongs.
	VolumeID string `json:"volumeID"`

	// The size of the volume to which the snapshot belongs.
	VolumeSize string `json:"volumeSize"`
}

// Volume provides information about a storage volume.
type Volume struct {
	// The volume's attachments.
	Attachments []*VolumeAttachment `json:"attachments"`

	// The availability zone for which the volume is available.
	AvailabilityZone string `json:"availabilityZone"`

	// The volume IOPs.
	IOPS int64 `json:"iops"`

	// The name of the volume.
	Name string `json:"name"`

	// The name of the network on which the volume resides.
	NetworkName string `json:"networkName"`

	// The size of the volume.
	Size string `json:"size"`

	// The volume status.
	Status string `json:"status"`

	// The volume ID.
	VolumeID string `json:"volumeID"`

	// The volume type.
	VolumeType string `json:"volumeType"`
}

// VolumeAttachment provides information about an object attached to a
// storage volume.
type VolumeAttachment struct {
	// The name of the device on which the volume to which the object is
	// attached is mounted.
	DeviceName string

	// The ID of the instance on which the volume to which the attachment
	// belongs is mounted.
	InstanceID *InstanceID

	// The status of the attachment.
	Status string

	// The ID of the volume to which the attachment belongs.
	VolumeID string
}
