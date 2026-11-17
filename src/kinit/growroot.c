#include <linux/blkpg.h>

#ifndef EXT4_IOC_RESIZE_FS
#define EXT4_IOC_RESIZE_FS _IOW('f', 16, uint64_t)
#endif

static long long sysfs_ll(const char *dir, const char *name)
{
	char p[PATH_MAX], b[64];
	snprintf(p, sizeof p, "%s/%s", dir, name);
	if (read_file(p, b, sizeof b) <= 0) return -1;
	return atoll(b);
}

static uint32_t le32(const unsigned char *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static int grow_mbr(const char *disk, long long start, long long size, long long disksz, int pno)
{
	char dev[PATH_MAX];
	snprintf(dev, sizeof dev, "/dev/%s", disk);
	int fd = open(dev, O_RDWR | O_CLOEXEC);
	if (fd < 0) { fprintf(stderr, "growroot: %s: %s\n", dev, strerror(errno)); return -1; }
	unsigned char mbr[512];
	if (pread(fd, mbr, 512, 0) != 512 || mbr[510] != 0x55 || mbr[511] != 0xAA) { close(fd); return 0; }
	int idx = -1;
	for (int i = 0; i < 4; i++) {
		unsigned char *e = mbr + 446 + 16 * i;
		if (e[4] == 0xEE) { close(fd); return 0; }
		if (e[4] && le32(e + 8) == start) idx = i;
		else if (e[4] && le32(e + 8) > start) { close(fd); return 0; }
	}
	if (idx < 0 || idx + 1 != pno) { close(fd); return 0; }
	long long want = (disksz - start) & ~2047LL;
	if (want > 0xffffffffLL) want = 0xffffffffLL & ~2047LL;
	if (want <= size) { close(fd); return 0; }
	unsigned char *e = mbr + 446 + 16 * idx;
	uint32_t w = (uint32_t)want;
	unsigned char nb[4] = { w & 0xff, (w >> 8) & 0xff, (w >> 16) & 0xff, w >> 24 };
	if (pwrite(fd, nb, 4, (e + 12) - mbr) != 4 || fsync(fd)) {
		fprintf(stderr, "growroot: writing the partition table failed: %s\n", strerror(errno));
		close(fd);
		return -1;
	}
	struct blkpg_partition bp = { .start = start * 512, .length = want * 512, .pno = pno };
	struct blkpg_ioctl_arg a = { .op = BLKPG_RESIZE_PARTITION, .datalen = sizeof bp, .data = &bp };
	int r = ioctl(fd, BLKPG, &a);
	close(fd);
	if (r) { fprintf(stderr, "growroot: resizing partition %d failed: %s (takes effect after a reboot)\n", pno, strerror(errno)); return -1; }
	printf("growroot: partition %d of %s grown from %lld to %lld MiB\n", pno, disk, size >> 11, want >> 11);
	return 1;
}

static int cmd_growroot(int argc, char **argv)
{
	const char *mnt = argc > 1 ? argv[1] : "/";
	struct stat st;
	if (stat(mnt, &st)) { fprintf(stderr, "growroot: %s: %s\n", mnt, strerror(errno)); return 1; }
	char sys[PATH_MAX], real[PATH_MAX];
	snprintf(sys, sizeof sys, "/sys/dev/block/%u:%u", major(st.st_dev), minor(st.st_dev));
	if (!realpath(sys, real)) { printf("growroot: %s is not on a block device, nothing to grow\n", mnt); return 0; }
	long long pno = sysfs_ll(real, "partition");
	long long start = sysfs_ll(real, "start");
	if (pno > 0 && start > 0) {
		char parent[PATH_MAX];
		snprintf(parent, sizeof parent, "%s", real);
		char *slash = strrchr(parent, '/');
		if (slash) {
			*slash = 0;
			const char *disk = strrchr(parent, '/');
			long long disksz = sysfs_ll(parent, "size");
			long long size = sysfs_ll(real, "size");
			if (disk && disksz > 0 && size > 0 && grow_mbr(disk + 1, start, size, disksz, (int)pno) < 0) return 1;
		}
	}
	struct statfs sf;
	if (statfs(mnt, &sf) || sf.f_type != 0xEF53) return 0;
	long long bytes = sysfs_ll(real, "size") * 512;
	if (bytes <= 0 || sf.f_bsize <= 0) return 0;
	uint64_t blocks = (uint64_t)bytes / (uint64_t)sf.f_bsize;
	char dev[PATH_MAX + 8];
	const char *base = strrchr(real, '/');
	snprintf(dev, sizeof dev, "/dev/%s", base ? base + 1 : real);
	for (int tries = 0;; tries++) {
		unsigned char sb[1024];
		int dfd = open(dev, O_RDONLY | O_CLOEXEC);
		if (dfd < 0) return 1;
		ssize_t got = pread(dfd, sb, sizeof sb, 1024);
		close(dfd);
		if (got != (ssize_t)sizeof sb || sb[56] != 0x53 || sb[57] != 0xEF) return 0;
		uint64_t cur = le32(sb + 4);
		if (le32(sb + 0x60) & 0x80) cur |= (uint64_t)le32(sb + 0x150) << 32;
		if (blocks <= cur + 256) return 0;
		int fd = open(mnt, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
		if (fd < 0) return 1;
		int r = ioctl(fd, EXT4_IOC_RESIZE_FS, &blocks);
		int err = errno;
		close(fd);
		if (!r) break;
		if (err == EBUSY && tries < 60) { sleep(1); continue; }
		fprintf(stderr, "growroot: ext4 online resize failed: %s\n", strerror(err));
		return 1;
	}
	printf("growroot: %s grown to %llu MiB\n", mnt, (unsigned long long)(bytes >> 20));
	return 0;
}
