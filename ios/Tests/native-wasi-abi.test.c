#include "../Sources/Engine/NativeWASIHostABI.h"
#include "../Sources/Engine/NativeTextHostABI.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

static int archive_test_fd = -1;
static int32_t archive_test_open(const char *relative) {
    if (strcmp(relative, "data/test.bin") != 0) return -2;
    return gta_wasi_register_readonly_fd(archive_test_fd);
}
static uint64_t le64(const unsigned char *p) {
    uint64_t n=0;
    for (unsigned i=0;i<8;i++) n|=(uint64_t)p[i]<<(8*i);
    return n;
}
static void write_le64(unsigned char *p, uint64_t x) {
    for (unsigned k=0;k<8;k++) p[k]=(unsigned char)(x>>(k*8));
}
int main(void) {
    unsigned char memory[80];
    memset(memory, 0xA5, sizeof(memory));
    gta_wasi_unbind_memory();
    assert(gta_wasi_clock_time_get(1, 1, 8)==21);
    assert(gta_wasi_environ_sizes_get(0, 8)==21);
    assert(gta_wasi_environ_get(0, 0)==21);
    gta_wasi_bind_memory(memory, sizeof memory);
    assert(gta_wasi_clock_time_get(1, 1, 8)==0);
    assert(le64(memory+8)>0);
    assert(gta_wasi_clock_time_get(0, 1000000, 16)==0);
    assert(le64(memory+16)>1000000000ULL);
    assert(gta_wasi_clock_time_get(999, 0, 32)==28);
    assert(gta_wasi_clock_time_get(1, 0, 76)==21);
    assert(gta_wasi_clock_time_get(1, 0, UINT64_MAX)==21);
    assert(memory[76]==0xA5);
    assert(gta_wasi_environ_sizes_get(24, 32)==0);
    assert(le64(memory+24)==0 && le64(memory+32)==0);
    assert(memory[40]==0xA5);
    assert(gta_wasi_environ_sizes_get(74, 32)==21);
    assert(gta_wasi_environ_sizes_get(UINT64_MAX, 0)==21);
    assert(gta_wasi_environ_get(80, 80)==0);
    assert(gta_wasi_environ_get(81, 80)==21);
    assert(gta_wasi_environ_get(80, UINT64_MAX)==21);
    /* WASI fd_write uses two u64 values per iovec with 64-bit pointers. */
    memory[4]='O'; memory[5]='K'; memory[6]='!';
    write_le64(memory+40,4);
    write_le64(memory+48,3);
    assert(gta_wasi_fd_write(1,40,1,64)==0);
    assert(le64(memory+64)==3);
    char line[256]={0};
    assert(gta_text_host_next_log(line,sizeof line)==1);
    assert(strstr(line,"[wasi-stdout] OK!")!=NULL);
    assert(gta_wasi_fd_write(2,40,1,64)==0);
    assert(gta_text_host_next_log(line,sizeof line)==1);
    assert(strstr(line,"[wasi-stderr] OK!")!=NULL);
    assert(gta_wasi_fd_write(7,40,1,64)==8);
    assert(gta_wasi_fd_write(1,40,257,64)==21);
    write_le64(memory+40,UINT64_MAX);
    assert(gta_wasi_fd_write(1,40,1,64)==28);
    write_le64(memory+40,4);
    assert(gta_wasi_fd_write(1,40,1,79)==21);
    /* Real standard-FD semantics for the engine's additional WASI ABI.
     * stdin reaches EOF; stdout/stderr cannot be read or seeked.
     * Foreign archive file descriptors remain EBADF, never process FDs.
     */
    assert(gta_wasi_fd_seek(0, 0, 0, 64)==70);
    assert(gta_wasi_fd_seek(1, -1, 1, 64)==70);
    assert(gta_wasi_fd_seek(99, 0, 0, 64)==8);
    assert(gta_wasi_fd_pread(0, 40, 1, 0, 64)==70);
    assert(gta_wasi_fd_pread(99, 40, 1, 0, 64)==8);
    assert(gta_wasi_fd_read(1, 40, 1, 64)==8);
    assert(gta_wasi_fd_read(2, 40, 1, 64)==8);
    write_le64(memory+40, 4);
    write_le64(memory+48, 3);
    memory[4]='Z';
    write_le64(memory+64, UINT64_MAX);
    assert(gta_wasi_fd_read(0, 40, 1, 64)==0);
    assert(le64(memory+64)==0 && memory[4]=='Z');
    assert(gta_wasi_fd_read(0, 40, 1, 79)==21);
    assert(gta_wasi_fd_read(0, 40, 257, 64)==21);
    write_le64(memory+40, UINT64_MAX);
    assert(gta_wasi_fd_read(0, 40, 1, 64)==21);

    /* Real, read-only guest descriptors backed by actual file contents.
     * The WASI fd is not a process fd; reads cannot escape the registered file.
     */
    char tmpname[]="/tmp/gta-wasi-test-XXXXXX";
    int actual=mkstemp(tmpname);
    assert(actual>=0);
    unlink(tmpname);
    const char *bytes="HELLO GTA ENGINE";
    assert(write(actual,bytes,16)==16);
    int32_t gamefd=gta_wasi_register_readonly_fd(actual);
    assert(gamefd>=3);
    /* Exercise the real memory64 openat guest path -> authorized provider
     * -> virtual guest FD; deny write flags and suspicious path traversal. */
    archive_test_fd=actual;
    gta_wasi_set_openat_provider(archive_test_open);
    strcpy((char*)memory, "data/test.bin");
    assert(gta_wasi_syscall_openat(-100,0,1,0)==-2);
    assert(gta_wasi_syscall_openat(7,0,O_RDONLY,0)==-8);
    assert(gta_wasi_syscall_openat(-100,UINT64_MAX,O_RDONLY,0)==-21);
    int32_t opened=gta_wasi_syscall_openat(-100,0,O_RDONLY,0);
    assert(opened>=3 && opened!=gamefd);
    assert(gta_wasi_fd_close((uint32_t)opened)==0);
    strcpy((char*)memory,"/game/test.bin");
    opened=gta_wasi_syscall_openat(-100,0,32768,0);
    assert(opened>=3);
    assert(gta_wasi_fd_close((uint32_t)opened)==0);
    /* Linux/Emscripten creation bits, independent of Darwin O_CREAT. */
    assert(gta_wasi_syscall_openat(-100,0,64,0)==-2);
    assert(gta_wasi_syscall_openat(-100,0,512,0)==-2);
    assert(gta_wasi_syscall_openat(-100,0,1024,0)==-2);
    strcpy((char*)memory,"data/../b/secret");
    assert(gta_wasi_syscall_openat(-100,0,O_RDONLY,0)==-2);
    strcpy((char*)memory,"data//broken");
    assert(gta_wasi_syscall_openat(-100,0,O_RDONLY,0)==-2);
    strcpy((char*)memory,"data/./broken");
    assert(gta_wasi_syscall_openat(-100,0,O_RDONLY,0)==-2);
    gta_wasi_set_openat_provider(NULL);
    archive_test_fd=-1;
    /* Real Emscripten stat64 memory64 struct and native calendar fields. */
    unsigned char large[192];
    memset(large,0xA5,sizeof large);
    gta_wasi_bind_memory(large,sizeof large);
    assert(gta_wasi_syscall_fstat64(gamefd,80)==0);
    assert(le64(large+112)==16);
    assert((large[85] & 0xF0) == 0x80); /* regular-file mode; unlinked temp file has nlink=0 */
    assert(gta_wasi_syscall_fstat64(-1,80)==-8);
    assert(gta_wasi_syscall_fstat64(gamefd,150)==-21);
    assert(gta_wasi_gmtime_js(0,0)==0);
    assert(large[20]==70 && large[16]==0);
    assert(gta_wasi_localtime_js(0,8)==0);
    assert(gta_wasi_localtime_js(0,150)==1);
    assert(gta_wasi_gmtime_js(0,170)==1);
    /* Emscripten's real currentPath, shell-disable and fcntl guest ABI. */
    assert(gta_wasi_syscall_getcwd(0,0)==-28);
    assert(gta_wasi_syscall_getcwd(0,1)==-68);
    assert(gta_wasi_syscall_getcwd(191,2)==-21);
    assert(gta_wasi_syscall_getcwd(0,2)==2);
    assert(large[0]=='/' && large[1]==0);
    assert(gta_wasi_emscripten_system(0)==0);
    assert(gta_wasi_emscripten_system(99)==-52);
    assert(gta_wasi_syscall_fcntl64(-1,3,0)==-8);
    assert(gta_wasi_syscall_fcntl64(gamefd,3,0)==0);
    assert(gta_wasi_syscall_fcntl64(gamefd,1,0)==0);
    assert(gta_wasi_syscall_fcntl64(gamefd,99,0)==-28);
    large[120]=7;large[121]=0;large[122]=0;large[123]=0;
    int32_t dup_guest=gta_wasi_syscall_fcntl64(gamefd,0,120);
    assert(dup_guest==7);
    assert(gta_wasi_fd_close((uint32_t)dup_guest)==0);
    assert(gta_wasi_syscall_fcntl64(gamefd,0,190)==-21);
    assert(gta_wasi_syscall_fcntl64(gamefd,0,120)==7);
    assert(gta_wasi_fd_close(7)==0);
    /* Source-accurate newfstatat/statfs64/timezone imports over actual
     * provider-approved file bytes and the guest's memory64 structures. */
    archive_test_fd=actual;
    gta_wasi_set_openat_provider(archive_test_open);
    strcpy((char*)large,"data/test.bin");
    assert(gta_wasi_syscall_newfstatat(-100,0,80,0)==0);
    assert(le64(large+112)==16);
    assert(gta_wasi_syscall_newfstatat(9,0,80,0)==-8);
    assert(gta_wasi_syscall_newfstatat(-100,191,80,0)==-21);
    assert(gta_wasi_syscall_newfstatat(-100,0,80,99999)==-28);
    assert(gta_wasi_syscall_statfs64(0,0,96)==0);
    assert(le64(large+112)>0); /* real filesystem blocks */
    large[60]=0;
    assert(gta_wasi_syscall_newfstatat(gamefd,60,80,4096)==0);
    assert(le64(large+112)==16);
    gta_wasi_set_openat_provider(NULL);
    archive_test_fd=-1;
    assert(gta_wasi_tzset_js(0,8,16,40)==0);
    assert(memcmp(large+16,"UTC",3)==0 && memcmp(large+40,"UTC",3)==0);
    assert(gta_wasi_tzset_js(190,8,16,40)==-21);
    gta_wasi_bind_memory(memory,sizeof memory);
    close(actual); /* guest owns a duplicate, not the source */
    write_le64(memory+40,4);
    write_le64(memory+48,5);
    assert(gta_wasi_fd_read((uint32_t)gamefd,40,1,64)==0);
    assert(le64(memory+64)==5 && memcmp(memory+4,"HELLO",5)==0);
    assert(gta_wasi_fd_seek((uint32_t)gamefd,6,0,72)==0);
    assert(le64(memory+72)==6);
    write_le64(memory+48,3);
    assert(gta_wasi_fd_read((uint32_t)gamefd,40,1,64)==0);
    assert(le64(memory+64)==3 && memcmp(memory+4,"GTA",3)==0);
    write_le64(memory+48,5);
    assert(gta_wasi_fd_pread((uint32_t)gamefd,40,1,0,64)==0);
    assert(memcmp(memory+4,"HELLO",5)==0);
    /* pread must leave the virtual sequential cursor at 9. */
    assert(gta_wasi_fd_seek((uint32_t)gamefd,0,1,72)==0);
    assert(le64(memory+72)==9);
    assert(gta_wasi_fd_seek((uint32_t)gamefd,-3,2,72)==0);
    assert(le64(memory+72)==13);
    assert(gta_wasi_fd_seek((uint32_t)gamefd,0,88,72)==28);
    assert(gta_wasi_fd_read((uint32_t)gamefd,40,257,64)==21);
    write_le64(memory+40,UINT64_MAX);
    assert(gta_wasi_fd_pread((uint32_t)gamefd,40,1,0,64)==21);
    assert(gta_wasi_fd_close((uint32_t)gamefd)==0);
    assert(gta_wasi_fd_close((uint32_t)gamefd)==8);
    assert(gta_wasi_fd_read((uint32_t)gamefd,40,1,64)==8);
    assert(gta_wasi_fd_close(5)==8);
    gta_wasi_unbind_memory();
    assert(gta_wasi_fd_read(0, 40, 1, 64)==21);
    assert(gta_wasi_fd_close(1)==0);
    assert(gta_wasi_fd_close(1)==8);
    assert(gta_wasi_fd_write(1,40,1,64)==8);
    assert(gta_wasi_fd_close(2)==0);
    assert(gta_wasi_fd_close(0)==0);
    assert(gta_wasi_fd_read(0, 40, 1, 64)==8);
    assert(gta_wasi_fd_seek(0, 0, 0, 64)==8);
    assert(gta_wasi_fd_close(0)==8);
    assert(gta_wasi_fd_write(1,40,1,64)==8);
    assert(gta_wasi_environ_sizes_get(0, 8)==21);
    assert(gta_wasi_clock_time_get(1, 0, 8)==21);
    gta_wasi_reset_files();
    printf("PASS: memory64 WASI stdio and real readonly virtual fd read/seek/pread; bounds, EOF and EBADF\n");
    return 0;
}
