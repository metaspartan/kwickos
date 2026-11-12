# KwickOS build orchestration (Linux host with Docker; binfmt/qemu-user for
# cross-arch userland: `docker run --privileged --rm tonistiigi/binfmt --install all`).
#
#   make ARCH=amd64            userland + kpkg + kernels + rootfs + images
#   make container ARCH=amd64  import the rootfs as a local Docker image
#   make test ARCH=amd64       boot tests (QEMU) + package compatibility matrix
#   make bench                 benchmarks vs Alpine
ARCH    ?= amd64
FLAVOR  ?= virt
KVER    ?= $(shell cat KERNEL_VERSION)
VERSION := $(shell cat VERSION)
OUT     ?= $(CURDIR)/out
BUILDER ?= kwick-builder
ALPINE  ?= alpine:3.22

RUN_BUILDER = docker run --rm -v $(CURDIR):/src -v $(OUT):/out -v kwick-build:/build -v kwick-cache:/cache \
              -e KVER=$(KVER) -e KWICK_REPO_URL -e KWICK_REPO_KEY -e KWICK_SIGNING_KEY $(BUILDER)
KVM := $(shell [ -w /dev/kvm ] && echo --device /dev/kvm)

.PHONY: all builder userland kpkg kernel kernel-generic rootfs images container repo test boot-test compat bench clean

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

rootfs:
	$(RUN_BUILDER) bash /src/scripts/mkrootfs.sh $(ARCH)

images:
	$(RUN_BUILDER) bash /src/scripts/mkimage.sh $(ARCH)

container:
	docker import --platform linux/$(ARCH) \
	  --change 'CMD ["/bin/sh"]' --change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
	  $(OUT)/$(ARCH)/kwickos-rootfs-$(ARCH).tar.gz kwickos:$(VERSION)-$(ARCH)

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
