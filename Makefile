ARCH    ?= amd64
FLAVOR  ?= virt
KVER    ?= $(shell cat KERNEL_VERSION)
VERSION := $(shell cat VERSION)
OUT     ?= $(CURDIR)/out
BUILDER ?= kwick-builder
ALPINE  ?= alpine:3.22
ROOTFS_TAR ?= $(OUT)/$(ARCH)/kwickos-rootfs-$(ARCH).tar.gz

RUN_BUILDER = docker run --rm -v $(CURDIR):/src -v $(OUT):/out -v kwick-build:/build -v kwick-cache:/cache \
              -e KVER=$(KVER) -e KWICK_REPO_URL -e KWICK_REPO_KEY -e KWICK_SIGNING_KEY $(BUILDER)
KVM := $(shell [ -w /dev/kvm ] && echo --device /dev/kvm)

.PHONY: all builder userland kpkg kernel kernel-generic zfs storage-pkg rootfs images headless-iso headless-iso-grub container repo test boot-test compat bench clean

all: userland kpkg kernel kernel-generic rootfs images

builder:
	docker build -t $(BUILDER) -f docker/Dockerfile.builder docker

userland:
	docker run --rm --platform linux/$(ARCH) -v $(CURDIR):/src -v $(OUT):/out -v kwick-cache:/cache $(ALPINE) \
	  sh /src/scripts/build-userland.sh $(ARCH)

kpkg:
	$(RUN_BUILDER) env ARCHES=$(ARCH) bash /src/scripts/build-kpkg.sh

kernel:
	$(RUN_BUILDER) bash /src/scripts/build-kernel.sh $(ARCH) virt $(KVER)

kernel-generic:
	$(RUN_BUILDER) bash /src/scripts/build-kernel.sh $(ARCH) generic $(KVER)

zfs:
	$(RUN_BUILDER) bash /src/scripts/mkzfspkg.sh $(ARCH) generic

storage-pkg:
	$(RUN_BUILDER) bash /src/scripts/mkstoragepkg.sh

rootfs:
	$(RUN_BUILDER) bash /src/scripts/mkrootfs.sh $(ARCH)

images:
	$(RUN_BUILDER) bash /src/scripts/mkimage.sh $(ARCH)

headless-iso:
	$(RUN_BUILDER) bash /src/scripts/mkheadless-iso.sh $(ARCH)

headless-iso-grub:
	$(RUN_BUILDER) env LIVE_BOOT=grub bash /src/scripts/mkheadless-iso.sh $(ARCH)

container:
	docker import --platform linux/$(ARCH) \
	  --change 'CMD ["/bin/sh"]' --change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
	  $(ROOTFS_TAR) kwickos:$(VERSION)-$(ARCH)

repo:
	$(RUN_BUILDER) bash -c 'for f in virt generic; do [ -f /out/$(ARCH)/kernel-$$f/version ] && bash /src/scripts/mkkernelpkg.sh $(ARCH) $$f; done; bash /src/scripts/mkrepo.sh'

boot-test:
	docker run --rm $(KVM) -v $(CURDIR):/src -v $(OUT):/out $(BUILDER) bash /src/tests/boot-matrix.sh $(ARCH)

compat: container
	bash tests/compat.sh kwickos:$(VERSION)-$(ARCH) 6

test: boot-test compat

bench:
	bash bench/run.sh

clean:
	rm -rf $(OUT)
