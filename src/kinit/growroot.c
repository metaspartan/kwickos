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

static uint64_t le64(const unsigned char *p)
{
	return le32(p) | (uint64_t)le32(p + 4) << 32;
}

static void put32(unsigned char *p, uint32_t v)
{
	for (int i = 0; i < 4; i++) p[i] = v >> (8 * i);
}

static void put64(unsigned char *p, uint64_t v)
{
	for (int i = 0; i < 8; i++) p[i] = v >> (8 * i);
}

static uint32_t gpt_crc32(const unsigned char *p, size_t n)
{
	uint32_t c = 0xffffffffu;
	while (n--) {
		c ^= *p++;
		for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1)));
	}
	return ~c;
}

static void gpt_seal(unsigned char *h, uint32_t hsz)
{
	put32(h + 16, 0);
	put32(h + 16, gpt_crc32(h, hsz));
}

static int pwrite_all(int fd, const void *b, size_t n, off_t off)
{
	return pwrite(fd, b, n, off) == (ssize_t)n ? 0 : -1;
}

static int resize_part(int fd, const char *disk, int pno, long long start, long long oldsz, long long newsz)
{
	struct blkpg_partition bp = { .start = start * 512, .length = newsz * 512, .pno = pno };
	struct blkpg_ioctl_arg a = { .op = BLKPG_RESIZE_PARTITION, .datalen = sizeof bp, .data = &bp };
	if (ioctl(fd, BLKPG, &a)) {
		fprintf(stderr, "growroot: resizing partition %d failed: %s (takes effect after a reboot)\n", pno, strerror(errno));
		return -1;
	}
	printf("growroot: partition %d of %s grown from %lld to %lld MiB\n", pno, disk, oldsz >> 11, newsz >> 11);
	return 1;
}

static int grow_gpt(int fd, const char *disk, long long start, long long size, long long disksz, int pno)
{
	char q[PATH_MAX];
	snprintf(q, sizeof q, "/sys/block/%s/queue", disk);
	long long lbs = sysfs_ll(q, "logical_block_size");
	if (lbs != 512 && lbs != 1024 && lbs != 2048 && lbs != 4096) lbs = 512;
	long long f = lbs / 512;
	if (start % f || disksz < 64 * f) return 0;
	int rc = -1;
	unsigned char *hdr = calloc(1, lbs), *bak = calloc(1, lbs), *ents = NULL, *pm = NULL;
	if (!hdr || !bak) goto out;
	if (pread(fd, hdr, lbs, lbs) != lbs || memcmp(hdr, "EFI PART", 8)) {
		fprintf(stderr, "growroot: %s has a protective MBR but no GPT header\n", disk);
		goto out;
	}
	uint32_t hsz = le32(hdr + 12);
	if (hsz < 92 || hsz > lbs) goto bad;
	uint32_t hcrc = le32(hdr + 16);
	put32(hdr + 16, 0);
	if (gpt_crc32(hdr, hsz) != hcrc) goto bad;
	put32(hdr + 16, hcrc);
	uint64_t entlba = le64(hdr + 72), alt = le64(hdr + 32), lastuse = le64(hdr + 48);
	uint32_t nent = le32(hdr + 80), esz = le32(hdr + 84);
	if (le64(hdr + 24) != 1 || esz < 128 || esz % 8 || nent == 0 || nent > 16384 || entlba < 2) goto bad;
	size_t asz = (size_t)nent * esz;
	uint64_t asec = (asz + lbs - 1) / lbs;
	ents = calloc(asec, lbs);
	if (!ents || pread(fd, ents, asec * lbs, entlba * lbs) != (ssize_t)(asec * lbs)) goto bad;
	if (gpt_crc32(ents, asz) != le32(hdr + 88)) goto bad;
	uint64_t last = (uint64_t)disksz / f - 1, pfirst = start / f;
	int idx = -1;
	uint64_t top = 0;
	for (uint32_t i = 0; i < nent; i++) {
		unsigned char *e = ents + (size_t)i * esz;
		int used = 0;
		for (int k = 0; k < 16; k++) used |= e[k];
		if (!used) continue;
		uint64_t fl = le64(e + 32), ll = le64(e + 40);
		if (fl == pfirst) idx = i;
		if (ll > top) top = ll;
	}
	if (idx < 0 || idx + 1 != pno) { rc = 0; goto out; }
	unsigned char *pe = ents + (size_t)idx * esz;
	uint64_t plast = le64(pe + 40);
	if (plast != top || plast < pfirst || alt > last || last < entlba + asec + asec + 2) { rc = 0; goto out; }
	uint64_t nlastuse = last - asec - 1;
	if (nlastuse < lastuse || nlastuse < plast) { rc = 0; goto out; }
	uint64_t al = 1048576 / lbs;
	uint64_t nend = (nlastuse + 1) / al * al - 1;
	if (nend < plast) nend = plast;
	if (nend == plast && alt == last) { rc = 0; goto out; }
	put64(pe + 40, nend);
	put64(hdr + 32, last);
	put64(hdr + 48, nlastuse);
	put32(hdr + 88, gpt_crc32(ents, asz));
	gpt_seal(hdr, hsz);
	memcpy(bak, hdr, lbs);
	put64(bak + 24, last);
	put64(bak + 32, 1);
	put64(bak + 72, last - asec);
	gpt_seal(bak, hsz);
	if (pwrite_all(fd, ents, asec * lbs, (off_t)(last - asec) * lbs) || pwrite_all(fd, bak, lbs, (off_t)last * lbs) || fsync(fd) ||
	    pwrite_all(fd, ents, asec * lbs, (off_t)entlba * lbs) || pwrite_all(fd, hdr, lbs, lbs) || fsync(fd)) {
		fprintf(stderr, "growroot: writing the GPT of %s failed: %s\n", disk, strerror(errno));
		goto out;
	}
	pm = calloc(1, 512);
	if (pm && pread(fd, pm, 512, 0) == 512 && pm[510] == 0x55 && pm[511] == 0xAA) {
		for (int i = 0; i < 4; i++) {
			unsigned char *e = pm + 446 + 16 * i;
			if (e[4] != 0xEE) continue;
			uint32_t w = last > 0xffffffffULL ? 0xffffffffu : (uint32_t)last;
			if (le32(e + 12) != w) {
				put32(e + 12, w);
				if (pwrite_all(fd, pm, 512, 0)) fprintf(stderr, "growroot: updating the protective MBR of %s failed: %s\n", disk, strerror(errno));
			}
			break;
		}
	}
	if (alt > nend && alt < last) {
		memset(bak, 0, lbs);
		pwrite_all(fd, bak, lbs, (off_t)alt * lbs);
	}
	fsync(fd);
	if (alt != last) printf("growroot: GPT backup header of %s moved to the end of the disk\n", disk);
	rc = nend > plast ? resize_part(fd, disk, pno, start, size, (long long)(nend - pfirst + 1) * f) : 0;
	goto out;
bad:
	fprintf(stderr, "growroot: the GPT of %s does not check out, leaving it alone\n", disk);
	rc = 0;
out:
	free(hdr);
	free(bak);
	free(ents);
	free(pm);
	return rc;
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
		if (e[4] == 0xEE) {
			int r = grow_gpt(fd, disk, start, size, disksz, pno);
			close(fd);
			return r;
		}
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
	int r = resize_part(fd, disk, pno, start, size, want);
	close(fd);
	return r;
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
