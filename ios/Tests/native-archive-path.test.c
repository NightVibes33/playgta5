#include "../Sources/Engine/NativeArchivePathABI.h"
#include <assert.h>
#include <string.h>

int main(void) {
    char path[128];
    assert(gta_archive_relative_path("/game/common/data/gameconfig.xml", path, sizeof path));
    assert(strcmp(path, "data/common/data/gameconfig.xml") == 0);
    assert(gta_archive_relative_path("/game/x64/textures/script_txds.rpf", path, sizeof path));
    assert(strcmp(path, "data/x64/textures/script_txds.rpf") == 0);
    assert(gta_archive_relative_path("game/common/test", path, sizeof path));
    assert(strcmp(path, "data/common/test") == 0);
    assert(gta_archive_relative_path("/data/manifest.json", path, sizeof path));
    assert(strcmp(path, "data/manifest.json") == 0);
    assert(gta_archive_relative_path("b/8b0b5899ed/game.wasm", path, sizeof path));
    const char *invalid[] = {"/game/../outside", "/game/./file", "/game//file",
        "//game/file", "/game/", "/game", "/unrelated/file", "", "data/../b/file"};
    for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i)
        assert(!gta_archive_relative_path(invalid[i], path, sizeof path));
    assert(!gta_archive_relative_path("/game/long", path, 5));
    assert(gta_archive_flags_readonly(0));
    assert(gta_archive_flags_readonly(32768)); /* Guest O_LARGEFILE */
    assert(gta_archive_flags_readonly(524288)); /* Guest O_CLOEXEC */
    const int denied[] = {1, 2, 3, 64, 128, 512, 1024, 32768 | 64};
    for (size_t i = 0; i < sizeof denied / sizeof denied[0]; ++i)
        assert(!gta_archive_flags_readonly(denied[i]));
    return 0;
}
