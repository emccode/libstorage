SHELL := /bin/bash

GO_VERSION := 1.8

ifeq (undefined,$(origin BUILD_TAGS))
BUILD_TAGS :=   gofig \
				pflag \
				libstorage_integration_driver_linux
ifneq (true,$(TRAVIS))
BUILD_TAGS +=   libstorage_storage_driver \
				libstorage_storage_driver_vfs \
				libstorage_storage_executor \
				libstorage_storage_executor_vfs
endif
endif

ifneq (,$(DRIVERS))
BUILD_TAGS += libstorage_storage_driver libstorage_storage_executor
BUILD_TAGS += $(foreach d,$(DRIVERS),libstorage_storage_driver_$(d) libstorage_storage_executor_$(d))
endif

ifneq (,$(BUILD_TAGS))
BUILD_TAGS := $(sort $(BUILD_TAGS))
endif


all:
# if docker is running, then let's use docker to build it
ifneq (,$(shell if docker version &> /dev/null; then echo -; fi))
	$(MAKE) docker-build
else
	$(MAKE) deps
	$(MAKE) build
endif

# record the paths to these binaries, if they exist
GO := $(strip $(shell which go 2> /dev/null))
GIT := $(strip $(shell which git 2> /dev/null))


################################################################################
##                               CONSTANTS                                    ##
################################################################################
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
ASTERIK := *
LPAREN := (
RPAREN := )
COMMA := ,
5S := $(SPACE)$(SPACE)$(SPACE)$(SPACE)$(SPACE)


################################################################################
##                               OS/ARCH INFO                                 ##
################################################################################
GOOS := $(strip $(GOOS))
GOARCH := $(strip $(GOARCH))

ifneq (,$(GO)) # if go exists
GOOS_GOARCH := $(subst /, ,$(shell $(GO) version | awk '{print $$4}'))
ifeq (,$(GOOS))
GOOS := $(word 1,$(GOOS_GOARCH))
endif
ifeq (,$(GOARCH))
GOARCH := $(word 2,$(GOOS_GOARCH))
endif
else
ifeq (,$(GOOS))
GOOS := $(shell uname -s | tr A-Z a-z)
endif
ifeq (,$(GOARCH))
GOARCH := amd64
endif
endif
GOOS_GOARCH := $(GOOS)_$(GOARCH)

ifeq (,$(OS))
ifeq ($(GOOS),windows)
OS := Windows_NT
endif
ifeq ($(GOOS),linux)
OS := Linux
endif
ifeq ($(GOOS),darwin)
OS := Darwin
endif
endif

ifeq (,$(ARCH))

ifeq ($(GOARCH),386)
ARCH := i386
endif # ifeq ($(GOARCH),386)

ifeq ($(GOARCH),amd64)
ARCH := x86_64
endif # ifeq ($(GOARCH),amd64)

ifeq ($(GOARCH),arm)
ifeq (,$(strip $(GOARM)))
GOARM := 7
endif # ifeq (,$(strip $(GOARM)))
ARCH := ARMv$(GOARM)
endif # ifeq ($(GOARCH),arm)

ifeq ($(GOARCH),arm64)
ARCH := ARMv8
endif # ifeq ($(GOARCH),arm64)

endif # ifeq (,$(ARCH))


# if GOARCH=arm & GOARM="" then figure out what
# the correct GOARM version is and export it
ifeq (arm,$(GOARCH))
ifeq (,$(strip $(GOARM)))
ifeq (ARMv5,$(ARCH))
GOARM := 5
endif # ifeq (ARMv5,$(ARCH))
ifeq (ARMv6,$(ARCH))
GOARM := 6
endif # ifeq (ARMv6,$(ARCH))
ifeq (ARMv7,$(ARCH))
GOARM := 7
endif # ifeq (ARMv7,$(ARCH))
endif # ifeq (,$(strip $(GOARM)))
export GOARM
endif # ifeq (arm,$(GOARCH))


# if GOARCH is arm64 then undefine & unexport GOARM
ifeq (arm64,$(GOARCH))
ifneq (undefined,$(origin GOARM))
undefine GOARM
unexport GOARM
endif
endif # ifeq ($(GOARCH),arm64)


# ensure that GOARM is compatible with the GOOS &
# GOARCH per https://github.com/golang/go/wiki/GoArm
# when GOARCH=arm
ifeq (arm,$(GOARCH))
ifeq (darwin,$(GOOS))
GOARM_ALLOWED := 7
else
GOARM_ALLOWED := 5 6 7
endif # ifeq (darwin,$(GOOS))
ifeq (,$(strip $(filter $(GOARM),$(GOARM_ALLOWED))))
$(info incompatible GOARM version: $(GOARM))
$(info allowed GOARM versions are: $(GOARM_ALLOWED))
$(info plese see https://github.com/golang/go/wiki/GoArm)
exit 1
endif # ifeq (,$(strip $(filter $(GOARM),$(GOARM_ALLOWED))))
endif # ifeq (arm,$(GOARCH))

export OS
export ARCH


################################################################################
##                                  DOCKER                                    ##
################################################################################
ifneq (,$(shell if docker version &> /dev/null; then echo -; fi))

DPKG := github.com/codedellemc/libstorage
DIMG := golang:$(GO_VERSION)
DGOHOSTOS := $(shell uname -s | tr A-Z a-z)
ifeq (undefined,$(origin DGOOS))
DGOOS := $(DGOHOSTOS)
endif
DGOARCH ?= amd64
DPRFX := build-libstorage
DNAME := $(DPRFX)
ifeq (1,$(DBUILD_ONCE))
DNAME := $(DNAME)-$(shell date +%s)
endif
DPATH := /go/src/$(DPKG)
DSRCS := $(shell git ls-files)
ifneq (,$(DGLIDE_YAML))
DSRCS := $(filter-out glide.yaml,$(DSRCS))
DSRCS := $(filter-out glide.lock,$(DSRCS))
DSRCS := $(filter-out glide.lock.d,$(DSRCS))
endif
DPROG1_NAME := lss-$(DGOOS)
DPROG1_PATH := /go/bin/$(DPROG1_NAME)
DPROG2_NAME := lsx-$(DGOOS)
DPROG2_PATH := /go/bin/$(DPROG2_NAME)
ifneq (linux,$(DGOOS))
DPROG1_PATH := /go/bin/$(DGOOS)_$(DGOARCH)/$(DPROG1_NAME)
DPROG2_PATH := /go/bin/$(DGOOS)_$(DGOARCH)/$(DPROG2_NAME)
endif
ifeq (darwin,$(DGOHOSTOS))
DTARC := -
endif
DIMG_EXISTS := docker images --format '{{.Repository}}:{{.Tag}}' | grep $(DIMG) &> /dev/null
DTO_CLOBBER := docker ps -a --format '{{.Names}}' | grep $(DPRFX)
DNETRC := $(HOME)/.netrc

# DLOCAL_IMPORTS specifics a list of imported packages to copy into the
# container build's vendor directory instead of what is specified in the
# glide.lock file. If this variable is set and the GOPATH variable is not
# then the target will fail.
ifeq (undefined,$(DLOCAL_IMPORTS))
DLOCAL_IMPORTS :=
endif
ifneq (,$(DLOCAL_IMPORTS))
ifneq (,$(GOPATH))
DLOCAL_IMPORTS_FILES := $(foreach I,$(DLOCAL_IMPORTS),$(addprefix $I/,$(shell git --git-dir=$(GOPATH)/src/$(I)/.git --work-tree=$(GOPATH)/src/$(I) ls-files)))
DLOCAL_IMPORTS_FILES += $(foreach I,$(DLOCAL_IMPORTS),$I/.git)
endif
endif

docker-init:
	@if ! $(DIMG_EXISTS); then docker pull $(DIMG); fi
	@docker run --name $(DNAME) -d $(DIMG) /sbin/init -D &> /dev/null || true && \
		docker exec $(DNAME) mkdir -p $(DPATH) && \
		tar -c $(DTARC) .git $(DSRCS) | docker cp - $(DNAME):$(DPATH)
ifneq (,$(DGLIDE_YAML))
	@docker cp $(DGLIDE_YAML) $(DNAME):$(DPATH)/glide.yaml
endif
ifneq (,$(wildcard $(DNETRC)))
	@docker cp $(DNETRC) $(DNAME):/root
endif
	docker exec -t $(DNAME) env make -C $(DPATH) deps
ifneq (,$(DLOCAL_IMPORTS))
ifeq (,$(GOPATH))
	@echo GOPATH must be set when using DLOCAL_IMPORTS && false
else
	@docker exec -t $(DNAME) rm -fr $(addprefix $(DPATH)/vendor/,$(DLOCAL_IMPORTS))
	@tar -C $(GOPATH)/src -c $(DTARC) $(DLOCAL_IMPORTS_FILES) | docker cp - $(DNAME):$(DPATH)/vendor
endif
endif
	docker exec -t $(DNAME) \
		env BUILD_TAGS="$(BUILD_TAGS)" GOOS=$(DGOOS) GOARCH=$(DGOARCH) DOCKER=1 \
		make -C $(DPATH) -j build

docker-build: docker-init
	@docker cp $(DNAME):$(DPROG1_PATH) $(DPROG1_NAME)
	@docker cp $(DNAME):$(DPROG2_PATH) $(DPROG2_NAME)
	@bytes=$$(stat --format '%s' $(DPROG1_NAME) 2> /dev/null || \
		stat -f '%z' $(DPROG1_NAME) 2> /dev/null) && mb=$$(($$bytes / 1024 / 1024)) && \
		printf "\nThe $(DPROG1_NAME) binary is $${mb}MB and located at: \n\n" && \
		printf "  ./$(DPROG1_NAME)\n\n"
	@bytes=$$(stat --format '%s' $(DPROG2_NAME) 2> /dev/null || \
		stat -f '%z' $(DPROG2_NAME) 2> /dev/null) && mb=$$(($$bytes / 1024 / 1024)) && \
		printf "\nThe $(DPROG2_NAME) binary is $${mb}MB and located at: \n\n" && \
		printf "  ./$(DPROG2_NAME)\n\n"
ifeq (1,$(DBUILD_ONCE))
	docker stop $(DNAME) &> /dev/null && docker rm $(DNAME) &> /dev/null
endif

docker-test: DGOOS=linux
docker-test: DTEST_ENV_VARS=TRAVIS=true LIBSTORAGE_DISABLE_STARTUP_INFO=true
docker-test: docker-init
	docker exec -t $(DNAME) \
		env BUILD_TAGS="$(BUILD_TAGS)" $(DTEST_ENV_VARS) \
		make -C $(DPATH) test

docker-clean:
	-docker stop $(DNAME) &> /dev/null && docker rm $(DNAME) &> /dev/null

docker-clobber:
	-CNAMES=$$($(DTO_CLOBBER)); if [ "$$CNAMES" != "" ]; then \
		docker stop $$CNAMES && docker rm $$CNAMES; \
	fi

docker-list:
	-$(DTO_CLOBBER)

endif # ifneq (,$(shell if docker version &> /dev/null; then echo -; fi))


################################################################################
##                                 CONSTANTS                                  ##
################################################################################
ifneq (,$(GO)) # if go exists


# a list of the go 1.6 stdlib pacakges as grepped from https://golang.org/pkg/
GO_STDLIB := archive archive/tar archive/zip bufio builtin bytes compress \
			 compress/bzip2 compress/flate compress/gzip compress/lzw \
			 compress/zlib container container/heap container/list \
			 container/ring crypto crypto/aes crypto/cipher crypto/des \
			 crypto/dsa crypto/ecdsa crypto/elliptic crypto/hmac crypto/md5 \
			 crypto/rand crypto/rc4 crypto/rsa crypto/sha1 crypto/sha256 \
			 crypto/sha512 crypto/subtle crypto/tls crypto/x509 \
			 crypto/x509/pkix database database/sql database/sql/driver debug \
			 debug/dwarf debug/elf debug/gosym debug/macho debug/pe \
			 debug/plan9obj encoding encoding/ascii85 encoding/asn1 \
			 encoding/base32 encoding/base64 encoding/binary encoding/csv \
			 encoding/gob encoding/hex encoding/json encoding/pem encoding/xml \
			 errors expvar flag fmt go go/ast go/build go/constant go/doc \
			 go/format go/importer go/parser go/printer go/scanner go/token \
			 go/types hash hash/adler32 hash/crc32 hash/crc64 hash/fnv html \
			 html/template image image/color image/color/palette image/draw \
			 image/gif image/jpeg image/png index index/suffixarray io \
			 io/ioutil log log/syslog math math/big math/cmplx math/rand mime \
			 mime/multipart mime/quotedprintable net net/http net/http/cgi \
			 net/http/cookiejar net/http/fcgi net/http/httptest \
			 net/http/httputil net/http/pprof net/mail net/rpc net/rpc/jsonrpc \
			 net/smtp net/textproto net/url os os/exec os/signal os/user path \
			 path/filepath reflect regexp regexp/syntax runtime runtime/cgo \
			 runtime/debug runtime/msan runtime/pprof runtime/race \
			 runtime/trace sort strconv strings sync sync/atomic syscall \
			 testing testing/iotest testing/quick text text/scanner \
			 text/tabwriter text/template text/template/parse time unicode \
			 unicode/utf16 unicode/utf8 unsafe context plugin


################################################################################
##                                SYSTEM INFO                                 ##
################################################################################

GOPATH := $(shell go env | grep GOPATH | sed 's/GOPATH="\(.*\)"/\1/')
GOPATH := $(word 1,$(subst :, ,$(GOPATH)))
GOHOSTOS := $(shell go env | grep GOHOSTOS | sed 's/GOHOSTOS="\(.*\)"/\1/')
GOHOSTARCH := $(shell go env | grep GOHOSTARCH | sed 's/GOHOSTARCH="\(.*\)"/\1/')
ifneq (,$(TRAVIS_GO_VERSION))
GOVERSION := $(TRAVIS_GO_VERSION)
else
GOVERSION := $(shell go version | awk '{print $$3}' | cut -c3-)
endif

ifeq ($(GO_VERSION),$(TRAVIS_GO_VERSION))
ifeq (linux,$(TRAVIS_OS_NAME))
COVERAGE_ENABLED := 1
endif
endif

# explicitly enable vendoring for Go 1.5.x versions.
GO15VENDOREXPERIMENT := 1

ifneq (,$(strip $(findstring 1.3.,$(TRAVIS_GO_VERSION))))
PRE_GO15 := 1
endif

ifneq (,$(strip $(findstring 1.4.,$(TRAVIS_GO_VERSION))))
PRE_GO15 := 1
endif

ifneq (1,$(PRE_GO15))
export GO15VENDOREXPERIMENT
endif


################################################################################
##                                  PATH                                      ##
################################################################################
export PATH := $(GOPATH)/bin:$(PATH)


################################################################################
##                               PROJECT INFO                                 ##
################################################################################

GO_LIST_BUILD_INFO_CMD := go list -f '{{with $$ip:=.}}{{with $$ctx:=context}}{{printf "%s %s %s %s %s 0,%s" $$ip.ImportPath $$ip.Name $$ip.Dir $$ctx.GOOS $$ctx.GOARCH (join $$ctx.BuildTags ",")}}{{end}}{{end}}'
ifneq (,$(BUILD_TAGS))
GO_LIST_BUILD_INFO_CMD += -tags "$(BUILD_TAGS)"
endif
BUILD_INFO := $(shell $(GO_LIST_BUILD_INFO_CMD))
ROOT_IMPORT_PATH := $(word 1,$(BUILD_INFO))
ROOT_IMPORT_PATH_NV := $(ROOT_IMPORT_PATH)
ROOT_IMPORT_NAME := $(word 2,$(BUILD_INFO))
ROOT_DIR := $(word 3,$(BUILD_INFO))
GOOS ?= $(word 4,$(BUILD_INFO))
GOARCH ?= $(word 5,$(BUILD_INFO))
VENDORED := 0
ifneq (,$(strip $(findstring vendor,$(ROOT_IMPORT_PATH))))
VENDORED := 1
ROOT_IMPORT_PATH_NV := $(shell echo $(ROOT_IMPORT_PATH) | sed 's/.*vendor\///g')
endif


################################################################################
##                                MAKE FLAGS                                  ##
################################################################################
ifeq (,$(MAKEFLAGS))
MAKEFLAGS := --no-print-directory
export $(MAKEFLAGS)
endif


################################################################################
##                              PROJECT DETAIL                                ##
################################################################################

GO_LIST_IMPORT_PATHS_INFO_CMD := go list -f '{{with $$ip:=.}}{{if $$ip.ImportPath | le "$(ROOT_IMPORT_PATH)"}}{{if $$ip.ImportPath | gt "$(ROOT_IMPORT_PATH)/vendor" }}{{printf "%s;%s;%s;%s;%v;0,%s,%s,%s,%s;0,%s;0,%s;0,%s" $$ip.ImportPath $$ip.Name $$ip.Dir $$ip.Target $$ip.Stale (join $$ip.GoFiles ",") (join $$ip.CgoFiles ",") (join $$ip.CFiles ",") (join $$ip.HFiles ",") (join $$ip.TestGoFiles ",") (join $$ip.Imports ",") (join $$ip.TestImports ",")}};{{end}}{{end}}{{end}}'
ifneq (,$(BUILD_TAGS))
GO_LIST_IMPORT_PATHS_INFO_CMD += -tags "$(BUILD_TAGS)"
endif
GO_LIST_IMPORT_PATHS_INFO_CMD += ./...
IMPORT_PATH_INFO := $(shell $(GO_LIST_IMPORT_PATHS_INFO_CMD))

# this runtime ruleset acts as a pre-processor, processing the import path
# information completely before creating the build targets for the project
define IMPORT_PATH_PREPROCS_DEF

IMPORT_PATH_INFO_$1 := $$(subst ;, ,$2)

DIR_$1 := $1
IMPORT_PATH_$1 := $$(word 1,$$(IMPORT_PATH_INFO_$1))
NAME_$1 := $$(word 2,$$(IMPORT_PATH_INFO_$1))
TARGET_$1 := $$(word 4,$$(IMPORT_PATH_INFO_$1))
STALE_$1 := $$(word 5,$$(IMPORT_PATH_INFO_$1))

ifeq (1,$$(DEBUG))
$$(info name=$$(NAME_$1), target=$$(TARGET_$1), stale=$$(STALE_$1), dir=$$(DIR_$1))
endif

SRCS_$1 := $$(subst $$(COMMA), ,$$(word 6,$$(IMPORT_PATH_INFO_$1)))
SRCS_$1 := $$(wordlist 2,$$(words $$(SRCS_$1)),$$(SRCS_$1))
SRCS_$1 := $$(addprefix $$(DIR_$1)/,$$(SRCS_$1))
SRCS += $$(SRCS_$1)

ifneq (,$$(strip $$(SRCS_$1)))
PKG_A_$1 := $$(TARGET_$1)
PKG_D_$1 := $$(DIR_$1)/$$(NAME_$1).d

ALL_PKGS += $$(PKG_A_$1)

DEPS_$1 := $$(subst $$(COMMA), ,$$(word 8,$$(IMPORT_PATH_INFO_$1)))
DEPS_$1 := $$(wordlist 2,$$(words $$(DEPS_$1)),$$(DEPS_$1))
DEPS_$1 := $$(filter-out $$(GO_STDLIB),$$(DEPS_$1))

INT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)/vendor/%,$$(DEPS_$1))
INT_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)%,$$(INT_DEPS_$1))

EXT_VENDORED_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)/vendor/%,$$(DEPS_$1))
EXT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)%,$$(DEPS_$1))
EXT_DEPS_$1 += $$(EXT_VENDORED_DEPS_$1)
EXT_DEPS += $$(EXT_DEPS_$1)
EXT_DEPS_SRCS_$1 := $$(addprefix $$(GOPATH)/src/,$$(addsuffix /*.go,$$(EXT_DEPS_$1)))
EXT_DEPS_SRCS_$1 := $$(subst $$(GOPATH)/src/$$(ROOT_IMPORT_PATH)/vendor/,./vendor/,$$(EXT_DEPS_SRCS_$1))
ifneq (,$$(filter $$(GOPATH)/src/C/%,$$(EXT_DEPS_SRCS_$1)))
EXT_DEPS_SRCS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(EXT_DEPS_SRCS_$1))
ifeq (main,$$(NAME_$1))
C_$1 := 1
endif
endif
EXT_DEPS_SRCS += $$(EXT_DEPS_SRCS_$1)

DEPS_ARKS_$1 := $$(addprefix $$(GOPATH)/pkg/$$(GOOS)_$$(GOARCH)/,$$(addsuffix .a,$$(INT_DEPS_$1)))
endif

TEST_SRCS_$1 := $$(subst $$(COMMA), ,$$(word 7,$$(IMPORT_PATH_INFO_$1)))
TEST_SRCS_$1 := $$(wordlist 2,$$(words $$(TEST_SRCS_$1)),$$(TEST_SRCS_$1))
TEST_SRCS_$1 := $$(addprefix $$(DIR_$1)/,$$(TEST_SRCS_$1))
TEST_SRCS += $$(TEST_SRCS_$1)

ifneq (,$$(strip $$(TEST_SRCS_$1)))
PKG_TA_$1 := $$(DIR_$1)/$$(NAME_$1).test
PKG_TD_$1 := $$(DIR_$1)/$$(NAME_$1).test.d
PKG_TC_$1 := $$(DIR_$1)/$$(NAME_$1).test.out

ALL_TESTS += $$(PKG_TA_$1)

-include $1/coverage.mk
TEST_COVERPKG_$1 ?= $$(IMPORT_PATH_$1)

TEST_DEPS_$1 := $$(subst $$(COMMA), ,$$(word 9,$$(IMPORT_PATH_INFO_$1)))
TEST_DEPS_$1 := $$(wordlist 2,$$(words $$(TEST_DEPS_$1)),$$(TEST_DEPS_$1))
TEST_DEPS_$1 := $$(filter-out $$(GO_STDLIB),$$(TEST_DEPS_$1))

TEST_INT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)/vendor/%,$$(TEST_DEPS_$1))
TEST_INT_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)%,$$(TEST_INT_DEPS_$1))

TEST_EXT_VENDORED_DEPS_$1 := $$(filter $$(ROOT_IMPORT_PATH)/vendor/%,$$(TEST_DEPS_$1))
TEST_EXT_DEPS_$1 := $$(filter-out $$(ROOT_IMPORT_PATH)%,$$(TEST_DEPS_$1))
TEST_EXT_DEPS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_$1))
TEST_EXT_DEPS_$1 += $$(TEST_EXT_VENDORED_DEPS_$1)
TEST_EXT_DEPS += $$(TEST_EXT_DEPS_$1)
TEST_EXT_DEPS_SRCS_$1 := $$(addprefix $$(GOPATH)/src/,$$(addsuffix /*.go,$$(TEST_EXT_DEPS_$1)))
TEST_EXT_DEPS_SRCS_$1 := $$(subst $$(GOPATH)/src/$$(ROOT_IMPORT_PATH)/vendor/,./vendor/,$$(TEST_EXT_DEPS_SRCS_$1))
ifneq (,$$(filter $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_SRCS_$1)))
TEST_EXT_DEPS_SRCS_$1 := $$(filter-out $$(GOPATH)/src/C/%,$$(TEST_EXT_DEPS_SRCS_$1))
ifeq (main,$$(NAME_$1))
TEST_C_$1 := 1
endif
endif

TEST_EXT_DEPS_SRCS += $$(TEST_EXT_DEPS_SRCS_$1)

TEST_DEPS_ARKS_$1 := $$(addprefix $$(GOPATH)/pkg/$$(GOOS)_$$(GOARCH)/,$$(addsuffix .a,$$(TEST_INT_DEPS_$1)))
endif

ALL_SRCS_$1 += $$(SRCS_$1) $$(TEST_SRCS_$1)
ALL_SRCS += $$(ALL_SRCS_$1)

endef
$(foreach i,\
	$(IMPORT_PATH_INFO),\
	$(eval $(call IMPORT_PATH_PREPROCS_DEF,$(subst $(ROOT_DIR),.,$(word 3,$(subst ;, ,$(i)))),$(i))))


################################################################################
##                                  INFO                                      ##
################################################################################
info:
	$(info Project Import Path.........$(ROOT_IMPORT_PATH))
ifeq (1,$(VENDORED))
	$(info No Vendor Import Path.......$(ROOT_IMPORT_PATH_NV))
endif
	$(info Project Name................$(ROOT_IMPORT_NAME))
	$(info OS / Arch...................$(OS)_$(ARCH))
	$(info Build Tags..................$(BUILD_TAGS))
	$(info Vendored....................$(VENDORED))
	$(info GOPATH......................$(GOPATH))
	$(info GOOS........................$(GOOS))
	$(info GOARCH......................$(GOARCH))
ifneq (,$(GOARM))
	$(info GOARM.......................$(GOARM))
endif
	$(info GOHOSTOS....................$(GOHOSTOS))
	$(info GOHOSTARCH..................$(GOHOSTARCH))
	$(info GOVERSION...................$(GOVERSION))
ifneq (,$(strip $(SRCS)))
	$(info Sources.....................$(patsubst ./%,%,$(firstword $(SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(SRCS)),$(SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(TEST_SRCS)))
	$(info Test Sources................$(patsubst ./%,%,$(firstword $(TEST_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(TEST_SRCS)),$(TEST_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(EXT_DEPS_SRCS)))
	$(info Dependency Sources..........$(patsubst ./%,%,$(firstword $(EXT_DEPS_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(EXT_DEPS_SRCS)),$(EXT_DEPS_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif
ifneq (,$(strip $(TEST_EXT_DEPS_SRCS)))
	$(info Test Dependency Sources.....$(patsubst ./%,%,$(firstword $(TEST_EXT_DEPS_SRCS))))
	$(foreach s,$(patsubst ./%,%,$(wordlist 2,$(words $(TEST_EXT_DEPS_SRCS)),$(TEST_EXT_DEPS_SRCS))),\
		$(info $(5S)$(5S)$(5S)$(5S)$(5S)$(SPACE)$(SPACE)$(SPACE)$(s)))
endif


################################################################################
##                               DEPENDENCIES                                 ##
################################################################################
GLIDE := $(GOPATH)/bin/glide
GLIDE_VER := 0.11.1
GLIDE_TGZ := glide-v$(GLIDE_VER)-$(GOHOSTOS)-$(GOHOSTARCH).tar.gz
GLIDE_URL := https://github.com/Masterminds/glide/releases/download/v$(GLIDE_VER)/$(GLIDE_TGZ)
GLIDE_LOCK := glide.lock
GLIDE_YAML := glide.yaml
GLIDE_LOCK_D := glide.lock.d

EXT_DEPS := $(sort $(EXT_DEPS))
EXT_DEPS_SRCS := $(sort $(EXT_DEPS_SRCS))
TEST_EXT_DEPS := $(sort $(TEST_EXT_DEPS))
TEST_EXT_DEPS_SRCS := $(sort $(TEST_EXT_DEPS_SRCS))
ALL_EXT_DEPS := $(sort $(EXT_DEPS) $(TEST_EXT_DEPS))
ALL_EXT_DEPS_SRCS := $(sort $(EXT_DEPS_SRCS) $(TEST_EXT_DEPS_SRCS))

ifneq (1,$(NODEPS))
ifneq (1,$(VENDORED))

$(GLIDE):
	@curl -SLO $(GLIDE_URL) && \
		tar xzf $(GLIDE_TGZ) && \
		rm -f $(GLIDE_TGZ) && \
		mkdir -p $(GOPATH)/bin && \
		mv $(GOHOSTOS)-$(GOHOSTARCH)/glide $(GOPATH)/bin && \
		rm -fr $(GOHOSTOS)-$(GOHOSTARCH)
glide: $(GLIDE)
GO_DEPS += $(GLIDE)

GO_DEPS += $(GLIDE_LOCK_D)
$(ALL_EXT_DEPS_SRCS): $(GLIDE_LOCK_D)

ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))
$(GLIDE_LOCK_D): $(GLIDE_LOCK) | $(GLIDE)
	touch $@

$(GLIDE_LOCK): $(GLIDE_YAML)
	$(GLIDE) up

else #ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))

$(GLIDE_LOCK_D): $(GLIDE_LOCK) | $(GLIDE)
	$(GLIDE) install && touch $@

$(GLIDE_LOCK): $(GLIDE_YAML)
	$(GLIDE) up && touch $@ && touch $(GLIDE_LOCK_D)

endif #ifeq (,$(strip $(wildcard $(GLIDE_LOCK))))

$(GLIDE_YAML):
	$(GLIDE) init

$(GLIDE_LOCK)-clean:
	rm -f $(GLIDE_LOCK)
GO_PHONY += $(GLIDE_LOCK)-clean
GO_CLOBBER += $(GLIDE_LOCK)-clean

endif #ifneq (1,$(VENDORED))
endif #ifneq (1,$(NODEPS))

################################################################################
##                                GOBINDATA                                   ##
################################################################################
GO_BINDATA := $(GOPATH)/bin/go-bindata
go-bindata: $(GO_BINDATA)

ifneq (1,$(NODEPS))

GO_BINDATA_IMPORT_PATH := vendor/github.com/jteeuwen/go-bindata/go-bindata
ifneq (1,$(VENDORED))
GO_BINDATA_IMPORT_PATH := $(ROOT_IMPORT_PATH)/$(GO_BINDATA_IMPORT_PATH)
else
GO_BINDATA_IMPORT_PATH := $(firstword $(subst /vendor/, ,$(ROOT_IMPORT_PATH)))/$(GO_BINDATA_IMPORT_PATH)
endif

ifneq (1,$(VENDORED))
$(GO_BINDATA): $(GLIDE_LOCK_D)
endif
$(GO_BINDATA):
	GOOS="" GOARCH="" go install $(GO_BINDATA_IMPORT_PATH)
	@touch $@
GO_DEPS += $(GO_BINDATA)

endif #ifneq (1,$(NODEPS))

################################################################################
##                               GOMETALINTER                                 ##
################################################################################
ifeq (1,$(PRE_GO15))
GOMETALINTER_DISABLED := 1
endif

ifneq (1,$(GOMETALINTER_DISABLED))
GOMETALINTER := $(GOPATH)/bin/gometalinter

ifneq (1,$(NODEPS))
$(GOMETALINTER): | $(GOMETALINTER_TOOLS)
	GOOS="" GOARCH="" go get -u github.com/alecthomas/gometalinter
gometalinter: $(GOMETALINTER)
GO_DEPS += $(GOMETALINTER)
endif # ifneq (1,$(NODEPS))

GOMETALINTER_TOOLS_D := .gometalinter.tools.d
$(GOMETALINTER_TOOLS_D): $(GOMETALINTER)
	GOOS="" GOARCH="" $(GOMETALINTER) --install --update && touch $@
GO_DEPS += $(GOMETALINTER_TOOLS_D)

GOMETALINTER_ARGS := --vendor \
					 --fast \
					 --cyclo-over=16 \
					 --deadline=30s \
					 --enable=gofmt \
					 --enable=goimports \
					 --enable=misspell \
					 --enable=lll \
					 --disable=gotype \
					 --severity=gofmt:error \
					 --severity=goimports:error \
					 --exclude=_generated.go \
					 --linter='gofmt:gofmt -l ./*.go:^(?P<path>[^\n]+)$''

gometalinter-warn: GOMETALINTER_ARGS += --line-length=80
gometalinter-warn: GOMETALINTER_ARGS += --severity=lll:warn
gometalinter-warn: GOMETALINTER_ARGS += --tests
gometalinter-warn: | $(GOMETALINTER_TOOLS_D) $(GLIDE)
	$(GOMETALINTER) $(GOMETALINTER_ARGS) $(shell $(GLIDE) nv)

gometalinter-error: GOMETALINTER_ARGS += --line-length=100
gometalinter-error: GOMETALINTER_ARGS += --severity=lll:error
gometalinter-error: | $(GOMETALINTER_TOOLS_D) $(GLIDE)
	$(GOMETALINTER) $(GOMETALINTER_ARGS) --errors $(shell $(GLIDE) nv)

gometalinter-all:
ifeq (1,$(GOMETALINTER_WARN_ENABLED))
	$(MAKE) gometalinter-warn
endif
	$(MAKE) gometalinter-error
else
gometalinter-all:
	@echo gometalinter disabled
endif


################################################################################
##                                  VERSION                                   ##
################################################################################

# figure out the git dirs
GIT_WORK:=.
GIT_ROOT:=.git
ifeq (1,$(VENDORED))
ifneq (,$(wildcard $(HOME)/.glide))
ROOT_IMPORT_PATH_DASH:=$(subst /,-,$(ROOT_IMPORT_PATH_NV))
VGIT_WORK:=$(shell find $(HOME)/.glide -name "*$(ROOT_IMPORT_PATH_DASH)" -type d)
ifneq (,$(wildcard $(VGIT_WORK)))
GIT_WORK:=$(VGIT_WORK)
ifneq (,$(wildcard $(VGIT_WORK)/.git))
GIT_ROOT:=$(VGIT_WORK)/.git
endif
endif
endif
endif

# parse a semver
SEMVER_PATT := ^[^\d]*(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z].+?))?(?:-(\d+)-g(.+?)(?:-(dirty))?)?$$
PARSE_SEMVER = $(shell echo $(1) | perl -pe 's/$(SEMVER_PATT)/$(2)/gim')

# describe the git information and create a parsing function for it
GIT_DESCRIBE := $(shell git --git-dir="$(GIT_ROOT)" --work-tree="$(GIT_WORK)" describe --long --dirty)
PARSE_GIT_DESCRIBE = $(call PARSE_SEMVER,$(GIT_DESCRIBE),$(1))

# parse the version components from the git information
V_MAJOR := $(call PARSE_GIT_DESCRIBE,$$1)
V_MINOR := $(call PARSE_GIT_DESCRIBE,$$2)
V_PATCH := $(call PARSE_GIT_DESCRIBE,$$3)
V_NOTES := $(call PARSE_GIT_DESCRIBE,$$4)
V_BUILD := $(call PARSE_GIT_DESCRIBE,$$5)
V_SHA_SHORT := $(call PARSE_GIT_DESCRIBE,$$6)
V_DIRTY := $(call PARSE_GIT_DESCRIBE,$$7)

V_OS := $(OS)
V_ARCH := $(ARCH)
V_OS_ARCH := $(V_OS)-$(V_ARCH)

# the long commit hash
V_SHA_LONG := $(shell git --git-dir="$(GIT_ROOT)" --work-tree="$(GIT_WORK)" show HEAD -s --format=%H)

# the branch name, possibly from travis-ci
ifeq ($(origin TRAVIS_BRANCH), undefined)
	TRAVIS_BRANCH := $(shell git --git-dir="$(GIT_ROOT)" --work-tree="$(GIT_WORK)" branch | grep '*')
else
ifeq (,$(strip $(TRAVIS_BRANCH)))
	TRAVIS_BRANCH := $(shell git --git-dir="$(GIT_ROOT)" --work-tree="$(GIT_WORK)" branch | grep '*')
endif
endif
TRAVIS_BRANCH := $(subst $(ASTERIK) ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)HEAD detached at ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)detached at ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)HEAD detached from ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(LPAREN)detached from ,,$(TRAVIS_BRANCH))
TRAVIS_BRANCH := $(subst $(RPAREN),,$(TRAVIS_BRANCH))

ifeq ($(origin TRAVIS_TAG), undefined)
	TRAVIS_TAG := $(TRAVIS_BRANCH)
else
	ifeq ($(strip $(TRAVIS_TAG)),)
		TRAVIS_TAG := $(TRAVIS_BRANCH)
	endif
endif
V_BRANCH := $(TRAVIS_TAG)

# the build date as an epoch
V_EPOCH := $(shell date +%s)

# the build date
V_BUILD_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%a, %d %b %Y %H:%M:%S %Z", localtime($(V_EPOCH)))')

# the release date as required by bintray
V_RELEASE_DATE := $(shell perl -e 'use POSIX strftime; print strftime("%Y-%m-%d", localtime($(V_EPOCH)))')

# init the semver
V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
ifneq ($(V_NOTES),)
	V_SEMVER := $(V_SEMVER)-$(V_NOTES)
endif

# get the version file's version
V_FILE := $(strip $(shell cat VERSION 2> /dev/null))

# append the build number and dirty values to the semver if appropriate
ifneq ($(V_BUILD),)
	ifneq ($(V_BUILD),0)
		# if the version file's version is different than the version parsed from the
		# git describe information then use the version file's version
		ifneq ($(V_SEMVER),$(V_FILE))
			V_MAJOR := $(call PARSE_SEMVER,$(V_FILE),$$1)
			V_MINOR := $(call PARSE_SEMVER,$(V_FILE),$$2)
			V_PATCH := $(call PARSE_SEMVER,$(V_FILE),$$3)
			V_NOTES := $(call PARSE_SEMVER,$(V_FILE),$$4)
			V_SEMVER := $(V_MAJOR).$(V_MINOR).$(V_PATCH)
			ifneq ($(V_NOTES),)
				V_SEMVER := $(V_SEMVER)-$(V_NOTES)
			endif
		endif
		V_SEMVER := $(V_SEMVER)+$(V_BUILD)
	endif
endif
ifeq ($(V_DIRTY),dirty)
	V_SEMVER := $(V_SEMVER)+$(V_DIRTY)
endif

define API_GENERATED_CONTENT
package api

import (
	"time"

	"github.com/codedellemc/libstorage/api/types"
)

func init() {
	Version = &types.VersionInfo{}
	Version.Arch = "$(V_OS_ARCH)"
	Version.Branch = "$(V_BRANCH)"
	Version.BuildTimestamp = time.Unix($(V_EPOCH), 0)
	Version.SemVer = "$(V_SEMVER)"
	Version.ShaLong = "$(V_SHA_LONG)"
}

endef
export API_GENERATED_CONTENT

PRINTF_VERSION_CMD += @printf "SemVer: %s\nBinary: %s\nBranch: %s\nCommit:
PRINTF_VERSION_CMD += %s\nFormed: %s\n" "$(V_SEMVER)" "$(V_OS_ARCH)"
PRINTF_VERSION_CMD += "$(V_BRANCH)" "$(V_SHA_LONG)" "$(V_BUILD_DATE)"
API_GENERATED_SRC := ./api/api_generated.go
$(API_GENERATED_SRC):
	echo generating $@
	@echo "$$API_GENERATED_CONTENT" > $@

$(API_GENERATED_SRC)-clean:
	rm -f $(API_GENERATED_SRC)
GO_CLEAN += $(API_GENERATED_SRC)-clean
GO_PHONE += $(API_GENERATED_SRC)-clean

API_A := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/api.a
$(API_A): $(API_GENERATED_SRC)

version:
	$(PRINTF_VERSION_CMD)

GO_PHONY += version


################################################################################
##                               PROJECT BUILD                                ##
################################################################################

define IMPORT_PATH_BUILD_DEF

ifneq (,$$(strip $$(SRCS_$1)))
ifneq (1,$$(C_$1))

DEPS_SRCS_$1 := $$(foreach d,$$(INT_DEPS_$1),$$(SRCS_.$$(subst $$(ROOT_IMPORT_PATH),,$$(d))))

$$(PKG_D_$1): $$(filter-out %_generated.go,$$(SRCS_$1))
	$$(file >$$@,$$(PKG_A_$1) $$(PKG_D_$1): $$(filter-out %_generated.go,$$(DEPS_SRCS_$1)))

-include $$(PKG_D_$1)

$$(PKG_D_$1)-clean:
	rm -f $$(PKG_D_$1)
GO_CLEAN += $$(PKG_D_$1)-clean

$$(PKG_A_$1): $$(EXT_DEPS_SRCS_$1) $$(SRCS_$1) | $$(DEPS_ARKS_$1)
ifeq (,$$(BUILD_TAGS))
	GOOS=$(GOOS) GOARCH=$(GOARCH) go install $1
else
	GOOS=$(GOOS) GOARCH=$(GOARCH) go install -tags "$$(BUILD_TAGS)" $1
endif

ifeq (true,$$(STALE_$1))
GO_PHONY += $$(PKG_A_$1)
endif

$$(PKG_A_$1)-clean:
	go clean -i -x $1 && rm -f $$(PKG_A_$1)

GO_BUILD += $$(PKG_A_$1)
GO_CLEAN += $$(PKG_A_$1)-clean

endif
endif


################################################################################
##                               PROJECT TESTS                                ##
################################################################################
ifneq (,$$(strip $$(TEST_SRCS_$1)))
ifneq (1,$$(TEST_C_$1))

TEST_DEPS_SRCS_$1 := $$(foreach d,$$(TEST_INT_DEPS_$1),$$(SRCS_.$$(subst $$(ROOT_IMPORT_PATH),,$$(d))))

$$(PKG_TD_$1): $$(filter-out %_generated.go,$$(TEST_SRCS_$1))
	$$(file >$$@,$$(PKG_TA_$1) $$(PKG_TD_$1): $$(filter-out %_generated.go,$$(TEST_DEPS_SRCS_$1)))

$$(PKG_TD_$1)-clean:
	rm -f $$(PKG_TD_$1)
GO_CLEAN += $$(PKG_TD_$1)-clean

-include $$(PKG_TD_$1)

ifneq (,$$(strip $$(PKG_A_$1)))
$$(PKG_TA_$1): $$(PKG_A_$1)
ifeq (true,$$(STALE_$1))
GO_PHONY += $$(PKG_TA_$1)
endif
endif
ifneq (,$$(strip $$(SRCS_$1)))
$$(PKG_TA_$1): $$(SRCS_$1)
endif

$$(PKG_TA_$1): $$(TEST_SRCS_$1) $$(TEST_EXT_DEPS_SRCS_$1) | $$(TEST_DEPS_ARKS_$1)
ifeq (,$$(BUILD_TAGS))
ifeq (1,$(COVERAGE_ENABLED))
	go test -cover -coverpkg '$$(TEST_COVERPKG_$1)' -c -o $$@ $1
else
	go test -c -o $$@ $1
endif
else
ifeq (1,$(COVERAGE_ENABLED))
	go test -cover -coverpkg '$$(TEST_COVERPKG_$1)' -tags "$$(BUILD_TAGS)" -c -o $$@ $1
else
	go test -tags "$$(BUILD_TAGS)" -c -o $$@ $1
endif
endif

$$(PKG_TA_$1)-clean:
	rm -f $$(PKG_TA_$1)
GO_PHONY += $$(PKG_TA_$1)-clean
GO_CLEAN += $$(PKG_TA_$1)-clean

$$(PKG_TC_$1): $$(PKG_TA_$1)
ifeq (1,$(COVERAGE_ENABLED))
	$$(PKG_TA_$1) -test.coverprofile $$@ $$(GO_TEST_FLAGS)
else
	$$(PKG_TA_$1) $$(GO_TEST_FLAGS) && touch $$@
endif
TEST_PROFILES += $$(PKG_TC_$1)

$$(PKG_TC_$1)-clean:
	rm -f $$(PKG_TC_$1)
GO_PHONY += $$(PKG_TC_$1)-clean

GO_TEST += $$(PKG_TC_$1)
GO_BUILD_TESTS += $$(PKG_TA_$1)
GO_CLEAN += $$(PKG_TC_$1)-clean

endif
endif

endef
$(foreach i,\
	$(IMPORT_PATH_INFO),\
	$(eval $(call IMPORT_PATH_BUILD_DEF,$(subst $(ROOT_DIR),.,$(word 3,$(subst ;, ,$(i)))),$(i))))


################################################################################
##                                  SCHEMA                                    ##
################################################################################
LIBSTORAGE_JSON := libstorage.json
LIBSTORAGE_SCHEMA_GENERATED := api/utils/schema/schema_generated.go
LIBSTORAGE_SCHEMA_A := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/api/utils/schema.a
$(LIBSTORAGE_SCHEMA_A): $(LIBSTORAGE_SCHEMA_GENERATED)

$(LIBSTORAGE_SCHEMA_GENERATED): $(LIBSTORAGE_JSON)
	@echo generating $@
	@printf "package schema\n\nconst (\n" >$@; \
		printf "\t// JSONSchema is the libStorage API JSON schema\n" >>$@; \
		printf "\tJSONSchema = \`" >>$@; \
		sed -e 's/^//' $< >>$@; \
		printf "\`\n)\n" >>$@;


################################################################################
##                                 EXECUTORS                                  ##
################################################################################

# handle which executors are embedded
ifeq (,$(strip $(EMED_EXECUTORS)))

ifeq (linux_amd64,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_LINUX_AMD64 ?= 1
endif
ifeq (linux_arm,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_LINUX_ARM ?= 1
endif
ifeq (linux_arm64,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_LINUX_ARM64 ?= 1
endif
ifeq (darwin_amd64,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_DARWIN_AMD64 ?= 1
endif
ifeq (darwin_arm,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_DARWIN_ARM ?= 1
endif
ifeq (darwin_arm64,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_DARWIN_ARM64 ?= 1
endif
ifeq (windows_amd64,$(GOOS)_$(GOARCH))
EMBED_EXECUTOR_WINDOWS_AMD64 ?= 1
endif

else

EMBED_EXECUTOR_LINUX_AMD64 := 0
EMBED_EXECUTOR_LINUX_ARM := 0
EMBED_EXECUTOR_LINUX_ARM64 := 0
EMBED_EXECUTOR_DARWIN_AMD64 := 0
EMBED_EXECUTOR_DARWIN_ARM := 0
EMBED_EXECUTOR_DARWIN_ARM64 := 0
EMBED_EXECUTOR_WINDOWS_AMD64 := 0

ifeq (linux_amd64,$(filter linux_amd64,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_LINUX_AMD64 := 1
endif
ifeq (linux_arm,$(filter linux_arm,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_LINUX_ARM := 1
endif
ifeq (linux_arm64,$(filter linux_arm64,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_LINUX_ARM64 := 1
endif
ifeq (darwin_amd64,$(filter darwin_amd64,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_DARWIN_AMD64 := 1
endif
ifeq (darwin_arm,$(filter darwin_arm,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_DARWIN_ARM := 1
endif
ifeq (darwin_arm64,$(filter darwin_arm64,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_DARWIN_ARM64 := 1
endif
ifeq (windows_amd64,$(filter windows_amd64,$(EMED_EXECUTORS)))
EMBED_EXECUTOR_WINDOWS_AMD64 := 1
endif

endif #ifneq (,$(strip $(EMED_EXECUTORS)))


EXECUTOR_LINUX := $(shell env GOOS=linux GOARCH=amd64 go list -f '{{.Target}}' ./cli/lsx/lsx-linux)
EXECUTOR_LINUX_ARM := $(shell env GOOS=linux GOARCH=arm go list -f '{{.Target}}' ./cli/lsx/lsx-linux)
EXECUTOR_LINUX_ARM64 := $(shell env GOOS=linux GOARCH=arm64 go list -f '{{.Target}}' ./cli/lsx/lsx-linux)
EXECUTOR_DARWIN := $(shell env GOOS=darwin GOARCH=amd64 go list -f '{{.Target}}' ./cli/lsx/lsx-darwin)
EXECUTOR_DARWIN_ARM := $(shell env GOOS=darwin GOARCH=arm go list -f '{{.Target}}' ./cli/lsx/lsx-darwin)
EXECUTOR_DARWIN_ARM64 := $(shell env GOOS=darwin GOARCH=arm64 go list -f '{{.Target}}' ./cli/lsx/lsx-darwin)
EXECUTOR_WINDOWS := $(shell env GOOS=windows GOARCH=amd64 go list -f '{{.Target}}' ./cli/lsx/lsx-windows)

EXECUTORS_BINDIR := ./api/server/executors/bin
EXECUTOR_LINUX_EMBED := $(EXECUTORS_BINDIR)/lsx-linux
EXECUTOR_LINUX_ARM_EMBED := $(EXECUTORS_BINDIR)/lsx-linux-arm
EXECUTOR_LINUX_ARM64_EMBED := $(EXECUTORS_BINDIR)/lsx-linux-arm64
EXECUTOR_DARWIN_EMBED := $(EXECUTORS_BINDIR)/lsx-darwin
EXECUTOR_DARWIN_ARM_EMBED := $(EXECUTORS_BINDIR)/lsx-darwin-arm
EXECUTOR_DARWIN_ARM64_EMBED := $(EXECUTORS_BINDIR)/lsx-darwin-arm64
EXECUTOR_WINDOWS_EMBED := $(EXECUTORS_BINDIR)/lsx-windows.exe

build-executor-linux: $(EXECUTOR_LINUX_EMBED)
build-executor-linux-arm: $(EXECUTOR_LINUX_ARM_EMBED)
build-executor-linux-arm64: $(EXECUTOR_LINUX_ARM64_EMBED)
build-executor-darwin: $(EXECUTOR_DARWIN_EMBED)
build-executor-darwin-arm: $(EXECUTOR_DARWIN_ARM_EMBED)
build-executor-darwin-arm64: $(EXECUTOR_DARWIN_ARM64_EMBED)
build-executor-windows: $(EXECUTOR_WINDOWS_EMBED)

clean-executor-linux:
	rm -f $(EXECUTOR_LINUX_EMBED)
clean-executor-linux-arm:
	rm -f $(EXECUTOR_LINUX_ARM_EMBED)
clean-executor-linux-arm64:
	rm -f $(EXECUTOR_LINUX_ARM64_EMBED)

clean-executor-darwin:
	rm -f $(EXECUTOR_DARWIN_EMBED)
clean-executor-darwin-arm:
	rm -f $(EXECUTOR_DARWIN_ARM_EMBED)
clean-executor-darwin-arm64:
	rm -f $(EXECUTOR_DARWIN_ARM64_EMBED)

clean-executor-windows:
	rm -f $(EXECUTOR_WINDOWS_EMBED)

EXECUTORS_GENERATED := ./api/server/executors/executors_generated.go
API_SERVER_EXECUTORS_A := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/api/server/executors.a

define EXECUTOR_RULES

LSX_EMBEDDED_$2_$3_FILENAME := $$(notdir $1)
LSX_EMBEDDED_$2_$3 := $$(EXECUTORS_BINDIR)/$$(LSX_EMBEDDED_$2_$3_FILENAME)

# add the GOARCH extension to the executor if the architecture is
# anything other than amd64
ifneq (amd64,$3)

# for windows platforms it's necessary to slice the .exe off the
# end of the executor filename and add the GOARCH before it
ifeq (windows,$2)
LSX_EMBEDDED_$2_$3_BASENAME := $$(basename $$(LSX_EMBEDDED_$2_$3_FILENAME))
LSX_EMBEDDED_$2_$3_BASEDIR := $$(EXECUTORS_BINDIR)/$$(LSX_EMBEDDED_$2_$3_BASENAME)
LSX_EMBEDDED_$2_$3 := $$(LSX_EMBEDDED_$2_$3_BASEDIR)-$3.exe

# simply add -GOARCH suffix to non-windows platforms
else
LSX_EMBEDDED_$2_$3 := $$(LSX_EMBEDDED_$2_$3)-$3
endif
endif

ifneq ($2_$3,$$(GOOS)_$$(GOARCH))
$1:
	BUILD_TAGS="$$(BUILD_TAGS)" GOOS="$2" GOARCH="$3" $$(MAKE) $$@
$1-clean:
	rm -f $1
	rm -f $(EXECUTORS_GENERATED)
GO_PHONY += $1-clean
GO_CLEAN += $1-clean
endif

$$(LSX_EMBEDDED_$2_$3): $1
	@mkdir -p $$(@D)
	cp -f $$? $$@

ifeq (linux,$2)

ifeq (amd64,$3)
ifeq (1,$$(EMBED_EXECUTOR_LINUX_AMD64))
EXECUTORS_EMBEDDED += $$(EXECUTOR_LINUX_EMBED)
endif
endif

ifeq (arm,$3)
ifeq (1,$$(EMBED_EXECUTOR_LINUX_ARM))
EXECUTORS_EMBEDDED += $$(EXECUTOR_LINUX_ARM_EMBED)
endif
endif # ifeq (arm,$$(GOARCH))

ifeq (arm64,$3)
ifeq (1,$$(EMBED_EXECUTOR_LINUX_ARM64))
EXECUTORS_EMBEDDED += $$(EXECUTOR_LINUX_ARM64_EMBED)
endif
endif # ifeq (arm64,$$(GOARCH))

endif # ifeq (linux,$2)

ifeq (darwin,$2)

ifeq (amd64,$3)
ifeq (1,$$(EMBED_EXECUTOR_DARWIN_AMD64))
EXECUTORS_EMBEDDED += $$(EXECUTOR_DARWIN_EMBED)
endif
endif

ifeq (arm,$3)
ifeq (1,$$(EMBED_EXECUTOR_DARWIN_ARM))
EXECUTORS_EMBEDDED += $$(EXECUTOR_DARWIN_ARM_EMBED)
endif
endif # ifeq (arm,$$(GOARCH))

ifeq (arm64,$3)
ifeq (1,$$(EMBED_EXECUTOR_DARWIN_ARM64))
EXECUTORS_EMBEDDED += $$(EXECUTOR_DARWIN_ARM64_EMBED)
endif
endif # ifeq (arm64,$$(GOARCH))

endif # ifeq (darwin,$2)

endef

$(eval $(call EXECUTOR_RULES,$(EXECUTOR_LINUX),linux,amd64))
$(eval $(call EXECUTOR_RULES,$(EXECUTOR_LINUX_ARM),linux,arm))
$(eval $(call EXECUTOR_RULES,$(EXECUTOR_LINUX_ARM64),linux,arm64))
$(eval $(call EXECUTOR_RULES,$(EXECUTOR_DARWIN),darwin,amd64))
$(eval $(call EXECUTOR_RULES,$(EXECUTOR_DARWIN_ARM),darwin,arm))
$(eval $(call EXECUTOR_RULES,$(EXECUTOR_DARWIN_ARM64),darwin,arm64))
#$(eval $(call EXECUTOR_RULES,$(EXECUTOR_WINDOWS),windows))

$(EXECUTORS_GENERATED): $(EXECUTORS_EMBEDDED)
	$(GO_BINDATA) -md5checksum -pkg executors -prefix $(@D)/bin -o $@ $(@D)/bin/...

$(EXECUTORS_GENERATED)-clean:
	rm -fr $(dir $(EXECUTORS_GENERATED))/bin
GO_PHONY += $(EXECUTORS_GENERATED)-clean
GO_CLEAN += $(EXECUTORS_GENERATED)-clean

$(API_SERVER_EXECUTORS_A): $(EXECUTORS_GENERATED)


################################################################################
##                                    C                                       ##
################################################################################
CC := gcc -Wall -pedantic -std=c99
ifneq (,$(wildcard /usr/include))
CC += -I/usr/include
endif


################################################################################
##                                  C CLIENT                                  ##
################################################################################
C_LIBSTOR_DIR := ./c
C_LIBSTOR_C_DIR := $(C_LIBSTOR_DIR)/libstor-c
C_LIBSTOR_C_SO := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/c/libstor-c.so
C_LIBSTOR_C_BIN := $(GOPATH)/bin/libstor-c
C_LIBSTOR_C_BIN_SRC := $(C_LIBSTOR_DIR)/libstor-c.c
C_LIBSTOR_C_GO_DEPS :=	$(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/api/types.a \
						$(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/client.a \

libstor-c: $(C_LIBSTOR_C_SO) $(C_LIBSTOR_C_BIN)

$(C_LIBSTOR_C_SO):  $(EXT_DEPS_SRCS_./c/libstor-c) \
					$(SRCS_./c/libstor-c) | $(DEPS_ARKS_./c/libstor-c)
ifeq (,$(BUILD_TAGS))
	go build -buildmode=c-shared -o $@ $(C_LIBSTOR_C_DIR)
else
	go build -tags "$(BUILD_TAGS)" -buildmode=c-shared -o $@ $(C_LIBSTOR_C_DIR)
endif

$(C_LIBSTOR_C_SO)-clean:
	rm -f $(C_LIBSTOR_C_SO) $(basename $(C_LIBSTOR_C_SO).h)
GO_PHONY += $(C_LIBSTOR_C_SO)-clean
GO_CLEAN += $(C_LIBSTOR_C_SO)-clean

$(C_LIBSTOR_C_BIN):  $(C_LIBSTOR_C_BIN_SRC) \
				 	 $(C_LIBSTOR_C_SO) \
					 $(C_LIBSTOR_C_GO_DEPS)
	$(CC) -I$(abspath $(C_LIBSTOR_C_DIR)) \
          -I$(dir $(C_LIBSTOR_C_SO)) \
          -L$(dir $(C_LIBSTOR_C_SO)) \
          -o $@ \
          $(C_LIBSTOR_C_BIN_SRC) \
          -lstor-c


################################################################################
##                                  C SERVER                                  ##
################################################################################
C_LIBSTOR_S_DIR := $(C_LIBSTOR_DIR)/libstor-s
C_LIBSTOR_S_SO := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/c/libstor-s.so
C_LIBSTOR_S_BIN := $(GOPATH)/bin/libstor-s
C_LIBSTOR_S_BIN_SRC := $(C_LIBSTOR_DIR)/libstor-s.c
C_LIBSTOR_S_GO_DEPS := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(ROOT_IMPORT_PATH)/api/server.a

libstor-s: $(C_LIBSTOR_S_BIN) $(C_LIBSTOR_S_SO)

$(C_LIBSTOR_S_SO):  $(EXT_DEPS_SRCS_./c/libstor-s) \
					$(SRCS_./c/libstor-s) | $(DEPS_ARKS_./c/libstor-s)
ifeq (,$(BUILD_TAGS))
	go build -buildmode=c-shared -o $@ $(C_LIBSTOR_S_DIR)
else
	go build -tags "$(BUILD_TAGS)" -buildmode=c-shared -o $@ $(C_LIBSTOR_S_DIR)
endif

$(C_LIBSTOR_S_SO)-clean:
	rm -f $(C_LIBSTOR_S_SO) $(basename $(C_LIBSTOR_S_SO).h)
GO_PHONY += $(C_LIBSTOR_S_SO)-clean
GO_CLEAN += $(C_LIBSTOR_S_SO)-clean

$(C_LIBSTOR_S_BIN):  $(C_LIBSTOR_TYPES_H) \
					 $(C_LIBSTOR_S_BIN_SRC) \
					 $(C_LIBSTOR_S_SO) \
					 $(C_LIBSTOR_S_GO_DEPS)
	$(CC) -I$(abspath $(C_LIBSTOR_DIR)) \
          -I$(dir $(C_LIBSTOR_S_SO)) \
          -L$(dir $(C_LIBSTOR_S_SO)) \
          -o $@ \
          $(C_LIBSTOR_S_BIN_SRC) \
          -lstor-s


################################################################################
##                                  SERVERS                                   ##
################################################################################
LSS_LINUX := $(shell GOOS=linux GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-linux)
LSS_LINUX_ARM := $(shell GOOS=linux GOARCH=arm go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-linux)
LSS_LINUX_ARM64 := $(shell GOOS=linux GOARCH=arm64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-linux)
LSS_DARWIN := $(shell GOOS=darwin GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-darwin)
LSS_DARWIN_ARM := $(shell GOOS=darwin GOARCH=arm go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-darwin)
LSS_DARWIN_ARM64 := $(shell GOOS=darwin GOARCH=arm64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-darwin)
LSS_WINDOWS := $(shell GOOS=windows GOARCH=amd64 go list -f '{{.Target}}' -tags '$(BUILD_TAGS)' ./cli/lss/lss-windows)

ifeq (linux,$(GOOS))
ifeq (amd64,$(GOARCH))
LSS := $(LSS_LINUX)
endif
ifeq (arm,$(GOARCH))
LSS := $(LSS_LINUX_ARM)
endif
ifeq (arm64,$(GOARCH))
LSS := $(LSS_LINUX_ARM64)
endif
endif # ifeq (linux,$(GOOS))

ifeq (darwin,$(GOOS))
ifeq (amd64,$(GOARCH))
LSS := $(LSS_DARWIN)
endif
ifeq (arm,$(GOARCH))
LSS := $(LSS_DARWIN_ARM)
endif
ifeq (arm64,$(GOARCH))
LSS := $(LSS_DARWIN_ARM64)
endif
endif # ifeq (darwin,$(GOOS))

ifeq (windows,$(GOOS))
LSS := $(LSS_WINDOWS)
endif # ifeq (windows,$(GOOS))

build-lss-linux: $(LSS_LINUX)
build-lss-linux-arm: $(LSS_LINUX_ARM)
build-lss-linux-arm64: $(LSS_LINUX_ARM64)
build-lss-darwin: $(LSS_DARWIN)
build-lss-darwin-arm: $(LSS_DARWIN_ARM)
build-lss-darwin-arm64: $(LSS_DARWIN_ARM64)
build-lss-windows: $(LSS_WINDOWS)

define LSS_RULES
ifneq ($2_$3,$$(GOOS)_$$(GOARCH))
$1:
	BUILD_TAGS="$$(BUILD_TAGS)" GOOS=$2 GOARCH=$3 $$(MAKE) $$@
$1-clean:
	rm -f $1
GO_PHONY += $1-clean
GO_CLEAN += $1-clean
endif

ifeq (linux,$2)

ifeq (amd64,$3)
LSS_ALL += $1
endif

ifeq (arm,$3)
ifeq (1,$$(BUILD_LSS_LINUX_ARM))
LSS_ALL += $1
endif
endif

ifeq (arm64,$3)
ifeq (1,$$(BUILD_LSS_LINUX_ARM64))
LSS_ALL += $1
endif
endif

endif
endef

#$(eval $(call LSS_RULES,$(LSS_LINUX),linux,amd64))
#$(eval $(call LSS_RULES,$(LSS_LINUX_ARM),linux,arm))
#$(eval $(call LSS_RULES,$(LSS_LINUX_ARM64),linux,arm64))
#$(eval $(call LSS_RULES,$(LSS_DARWIN),darwin,amd64))
#$(eval $(call LSS_RULES,$(LSS_DARWIN_ARM),darwin,arm))
#$(eval $(call LSS_RULES,$(LSS_DARWIN_ARM64),darwin,arm64))
#$(eval $(call LSS_RULES,$(LSS_WINDOWS),windows,amd64))


################################################################################
##                                  COVERAGE                                  ##
################################################################################
COVERAGE := coverage.out
GO_COVERAGE := $(COVERAGE)
$(COVERAGE): $(TEST_PROFILES)
	printf "mode: set\n" > $@
	$(foreach f,$?,grep -v "mode: set" $(f) >> $@ &&) true

$(COVERAGE)-clean:
	rm -f $(COVERAGE)
GO_CLEAN += $(COVERAGE)-clean
GO_PHONY += $(COVERAGE)-clean

cover: $(COVERAGE)
ifneq (1,$(CODECOV_OFFLINE))
ifeq (1,$(COVERAGE_ENABLED))
	curl -sSL https://codecov.io/bash | bash -s -- -f $?
else
	@echo codecov enabled only for linux+go1.6.3
endif
else
	@echo codecov offline
endif

.coverage.tools.d:
ifeq (1,$(COVERAGE_ENABLED))
	GOOS="" GOARCH="" go get github.com/onsi/gomega \
           github.com/onsi/ginkgo \
           golang.org/x/tools/cmd/cover && touch $@
else
	GOOS="" GOARCH="" go get golang.org/x/tools/cmd/cover && touch $@
endif
GO_DEPS += .coverage.tools.d

cover-debug:
	env LIBSTORAGE_DEBUG=true $(MAKE) cover


################################################################################
##                                  TARGETS                                   ##
################################################################################
ifeq (1,$(NODEPS))
deps:
	@echo nodeps
else
deps: $(GO_DEPS)
endif

build-tests: $(GO_BUILD_TESTS)

build-lsx: $(EXECUTORS_EMBEDDED)

build-lss: $(LSS_ALL)

build-libstorage: $(GO_BUILD)

build-generated:
	$(MAKE) build-lsx
	$(MAKE) $(API_GENERATED_SRC)

build-client-nogofig:
	go build ./client


clean-build:
	rm -fr $(API_GENERATED_SRC) \
	       $(EXECUTORS_BINDIR) \
	       $(EXECUTORS_GENERATED) \
	       $(GOPATH)/bin/lsx-* \
	       $(GOPATH)/bin/*/lsx-*
	$(MAKE) build

build:
	$(MAKE) build-generated
	$(MAKE) build-libstorage
ifeq ($(GOOS)_$(GOARCH),$(GOHOSTOS)_$(GOHOSTARCH))
	$(MAKE) libstor-c libstor-s
endif
	$(MAKE) build-lss

parallel-test: $(filter-out ./drivers/storage/vfs/%,$(GO_TEST))
vfs-test: $(filter ./drivers/storage/vfs/%,$(GO_TEST))
test:
	$(MAKE) vfs-test
	$(MAKE) -j parallel-test

test-debug:
	LIBSTORAGE_DEBUG=true $(MAKE) test

test-azureud:
	DRIVERS=azureud $(MAKE) deps
	DRIVERS=azureud $(MAKE) ./drivers/storage/azureud/tests/azureud.test

test-azureud-clean:
	DRIVERS=azureud $(MAKE) clean

test-dobs:
	DRIVERS=dobs $(MAKE) deps
	DRIVERS=dobs $(MAKE) ./drivers/storage/dobs/tests/dobs.test

test-dobs-clean:
	DRIVERS=dobs $(MAKE) clean

test-ebs:
	DRIVERS=ebs $(MAKE) deps
	DRIVERS=ebs $(MAKE) ./drivers/storage/ebs/tests/ebs.test

test-ebs-clean:
	DRIVERS=ebs $(MAKE) clean

test-efs:
	DRIVERS=efs $(MAKE) deps
	DRIVERS=efs $(MAKE) ./drivers/storage/efs/tests/efs.test

test-efs-clean:
	DRIVERS=efs $(MAKE) clean

test-fittedcloud:
	DRIVERS=fittedcloud $(MAKE) deps
	DRIVERS=fittedcloud $(MAKE) ./drivers/storage/fittedcloud/tests/fittedcloud.test

test-fittedcloud-clean:
	DRIVERS=fittedcloud $(MAKE) clean

test-gcepd:
	DRIVERS=gcepd $(MAKE) deps
	DRIVERS=gcepd $(MAKE) ./drivers/storage/gcepd/tests/gcepd.test

test-gcepd-clean:
	DRIVERS=gcepd $(MAKE) clean

test-rbd:
	DRIVERS=rbd $(MAKE) deps
	DRIVERS=rbd $(MAKE) ./drivers/storage/rbd/tests/rbd.test

test-rbd-clean:
	DRIVERS=rbd $(MAKE) clean


test-vfs:
	DRIVERS=vfs $(MAKE) ./drivers/storage/vfs/tests/vfs.test

test-cinder:
	DRIVERS=cinder $(MAKE) deps
	DRIVERS=cinder $(MAKE) ./drivers/storage/cinder/tests/cinder.test

test-cinder-clean:
	DRIVERS=cinder $(MAKE) clean

clean: $(GO_CLEAN)

clobber: clean $(GO_CLOBBER)

.PHONY: info clean clobber $(GO_PHONY)

endif # ifneq (,$(shell which go 2> /dev/null))
