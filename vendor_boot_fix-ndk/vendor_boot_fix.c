#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>

#define VNDRBOOT_MAGIC "VNDRBOOT"
#define VNDRBOOT_MAGIC_SIZE 8

/*
 * About the structure of the vendor_boot partition:
 * https://source.android.com/docs/core/architecture/partitions/vendor-boot-partitions
 */

static inline int goto_next_page_head(FILE *file, uint32_t page_size) {
	return fseek(file, page_size - (ftell(file) % page_size), SEEK_CUR);
}

int main(int argc, char *argv[]) {
	int rc = 1;
	char *vb_img;
	char magic[VNDRBOOT_MAGIC_SIZE];
	uint32_t header_version, page_size, vendor_ramdisk_size, header_size,
		 dtb_size, ramdisk_table_entry_num, first_vendor_ramdisk_size;
	long int local_first_vendor_ramdisk_size;
	FILE *file;

	if (argc != 2) {
		fprintf(stderr, "Usage: %s <vendor_boot image>\n", argv[0]);
		return rc;
	}

	vb_img = argv[1];
	file = fopen(vb_img, "rb+");
	if (!file) {
		perror("Failed to open file");
		return rc;
	}

	/* Validate the header */
	fread(magic, 1, VNDRBOOT_MAGIC_SIZE, file);
	if (memcmp(magic, VNDRBOOT_MAGIC, VNDRBOOT_MAGIC_SIZE) != 0) {
		fprintf(stderr, "Error: Invalid vendor_boot image!\n");
		goto close_and_exit;
	}
	fread(&header_version, sizeof(header_version), 1, file);
	if (header_version != 4) {
		fprintf(stderr, "Error: Invalid vendor_boot image!\n");
		goto close_and_exit;
	}

	/* Read page_size */
	fread(&page_size, sizeof(page_size), 1, file);

	/* Skip kernel_addr, ramdisk_addr */
	fseek(file, 4 + 4, SEEK_CUR); 

	/* Read vendor_ramdisk size.
	 * If there are multiple vendor_ramdisks, then this value is the sum of the sizes of all vendor_ramdisks.
	 */
	fread(&vendor_ramdisk_size, sizeof(vendor_ramdisk_size), 1, file);

	/* Skip cmdline, tags_addr, name */
	fseek(file, 2048 + 4 + 16, SEEK_CUR); 

	/* Read header_size, dtb_size */
	fread(&header_size, sizeof(header_size), 1, file);
	fread(&dtb_size, sizeof(dtb_size), 1, file);

	/* Skip dtb_addr, vendor_ramdisk_table_size */
	fseek(file, 8 + 4, SEEK_CUR); 

	/* Read ramdisk_table_entry_num */
	fread(&ramdisk_table_entry_num, sizeof(ramdisk_table_entry_num), 1, file);
	/* We don't do anything with images that have multiple vendor_ramdisks */
	if (ramdisk_table_entry_num != 1) {
		fprintf(stderr, "Multiple vendor_ramdisk entries found, skipping processing.\n");
		rc = 2;
		goto close_and_exit;
	}

	/* Locate to the first vendor_ramdisk table entry */
	fseek(file, header_size, SEEK_SET);
	goto_next_page_head(file, page_size);
	fseek(file, vendor_ramdisk_size, SEEK_CUR);
	goto_next_page_head(file, page_size);
	fseek(file, dtb_size, SEEK_CUR);
	goto_next_page_head(file, page_size);

	local_first_vendor_ramdisk_size = ftell(file);
	fread(&first_vendor_ramdisk_size, sizeof(first_vendor_ramdisk_size), 1, file);

	if (first_vendor_ramdisk_size == vendor_ramdisk_size) {
		printf("Nothing to do.\n");
		rc = 2;
		goto close_and_exit;
	}

	/* Make the size of the only vendor_ramdisk consistent with the sum of the sizes of all vendor_ramdisks.
	 * Otherwise, magiskboot will not be able to unpack the vendor_boot image normally.
	 */
	fseek(file, local_first_vendor_ramdisk_size, SEEK_SET);
	fwrite(&vendor_ramdisk_size, sizeof(vendor_ramdisk_size), 1, file);

	rc = 0;
	printf("Done!\n");

close_and_exit:
	fclose(file);
	return rc;
}
