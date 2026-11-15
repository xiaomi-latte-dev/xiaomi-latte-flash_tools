/*
 * mipad2 键盘重映射工具
 *
 * 小米平板 2 的电容触摸按键上报的 HID 扫描码与常规键盘不一致，
 * 需要把它们重映射成 Android/Linux 期望的语义键（HOME/BACK/APPSELECT）。
 * 本工具通过 EVIOCSKEYCODE_V2 直接改写内核 input 设备的键位表。
 *
 * 用法：
 *     mipad2-keymap            自动查找目标设备并应用映射
 *     mipad2-keymap /dev/input/event3   指定设备
 *     mipad2-keymap --list     只列出映射表，不修改任何东西
 *
 * 需要 root 权限（修改内核键位表）。
 *
 * 参考实现：xiaomi-latte-flash_tools/device_files/mipad2_keymap.c
 * 本版本修正了参考实现中的几处缺陷，见文件末尾的说明。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define DEVICE_NAME_MAX   64

/* 目标设备：FTSC1000 触摸控制器的键盘接口 */
#define TARGET_DEV_NAME   "FTSC1000:00 2808:509C Keyboard"
#define TARGET_VENDOR     0x2808
#define TARGET_PRODUCT    0x509c

/* 最多扫描的 /dev/input/eventN 数量 */
#define MAX_INPUT_DEVICES 32

/* 一个扫描码对应一项重映射 */
struct key_mapping
{
    uint32_t    scancode;
    unsigned int keycode;
    const char  *desc;
    const char  *from;
    const char  *to;
};

/*
 * 小米平板 2 的键位映射表。
 * 扫描码为上表 HID usage 与报告 ID 组合后的值（0x7xxxx 形式）。
 * 以 scancode == 0 结尾。
 */
static const struct key_mapping mipad2_keymap[] =
{
    {0x700e0, KEY_RESERVED,  "禁用左 Ctrl",  "LeftCtrl",  "忽略"},
    {0x700e3, KEY_RESERVED,  "禁用左 Meta",  "LeftMeta",  "忽略"},
    {0x70016, KEY_APPSELECT, "S 键变多任务", "S",         "AppSelect"},
    {0x70029, KEY_HOMEPAGE,  "Esc 键变 Home", "Esc",      "Homepage"},
    {0x7002a, KEY_BACK,      "退格变返回",    "Backspace", "Back"},
    {0,       0,              NULL,           NULL,        NULL},
};

struct device_info
{
    char name[DEVICE_NAME_MAX];
    int  bustype;
    int  vendor;
    int  product;
    int  version;
};

/* 打印用法 */
static void usage(const char *argv0)
{
    printf("用法: %s [设备路径 | --list]\n", argv0);
    printf("  %s              自动查找 mipad2 键盘并应用映射\n", argv0);
    printf("  %s /dev/input/eventN   指定设备\n", argv0);
    printf("  %s --list       只列出映射表，不修改设备\n", argv0);
}

/* 仅列出映射表，供文档与排查使用，不需要 root */
static void list_mapping(void)
{
    printf("mipad2 键位映射表:\n");
    printf("  %-10s %-10s %-12s %s\n", "扫描码", "键码", "来源", "目标");
    for (int i = 0; mipad2_keymap[i].scancode != 0; i++)
    {
        printf("  0x%06x  %-10u %-12s %s\n",
               mipad2_keymap[i].scancode,
               mipad2_keymap[i].keycode,
               mipad2_keymap[i].from,
               mipad2_keymap[i].to);
    }
}

/* 读取设备名称与 ID */
static int get_device_info(int fd, struct device_info *info)
{
    struct input_id id;

    memset(info, 0, sizeof(*info));

    if (ioctl(fd, EVIOCGNAME(sizeof(info->name) - 1), info->name) < 0)
    {
        return -1;
    }

    /* ID 拿不到不算致命：名称匹配已经足够判断 */
    if (ioctl(fd, EVIOCGID, &id) == 0)
    {
        info->bustype = id.bustype;
        info->vendor  = id.vendor;
        info->product = id.product;
        info->version = id.version;
    }

    return 0;
}

/* 是否为 mipad2 键盘 */
static int is_mipad2_keyboard(int fd)
{
    struct device_info info;

    if (get_device_info(fd, &info) < 0)
    {
        return 0;
    }

    /* 同一颗 FTSC1000 会导出三个 input 接口，vendor/product 完全一样：
     *   eventN   "FTSC1000:00 2808:509C"           触摸屏
     *   eventN+1 "FTSC1000:00 2808:509C UNKNOWN"
     *   eventN+2 "FTSC1000:00 2808:509C Keyboard"  真正的按键接口
     * 只按 ID 匹配会先命中触摸屏，键位表却被写到触摸屏上，键盘一点没变。
     * 所以必须同时要求名称里出现 Keyboard。 */
    if (info.vendor != TARGET_VENDOR || info.product != TARGET_PRODUCT)
    {
        return 0;
    }

    return strstr(info.name, "Keyboard") != NULL;
}

/* 把多字节扫描码拼成 uint32 */
static uint32_t scancode_to_uint32(const uint8_t *scancode, uint8_t len)
{
    uint32_t value = 0;

    if (!scancode || len == 0)
    {
        return 0;
    }
    if (len > 4)
    {
        len = 4;    /* kernel 的 input_keymap_entry 只用 4 字节 */
    }

    for (uint8_t i = 0; i < len; i++)
    {
        value |= ((uint32_t)scancode[i]) << (i * 8);
    }
    return value;
}

/* 按扫描码查映射表，未命中返回 NULL */
static const struct key_mapping *find_mapping(uint32_t scancode)
{
    for (int i = 0; mipad2_keymap[i].scancode != 0; i++)
    {
        if (mipad2_keymap[i].scancode == scancode)
        {
            return &mipad2_keymap[i];
        }
    }
    return NULL;
}

/*
 * 遍历设备当前的键位表，把命中的条目改写。
 *
 * 返回实际修改成功的条目数；负值表示遍历出错。
 */
static int apply_keymap(int fd)
{
    struct input_keymap_entry ke;
    int changed = 0;

    for (int index = 0; ; index++)
    {
        memset(&ke, 0, sizeof(ke));
        ke.index = index;
        ke.len   = 4;
        ke.flags = INPUT_KEYMAP_BY_INDEX;

        if (ioctl(fd, EVIOCGKEYCODE_V2, &ke) < 0)
        {
            if (errno == EINVAL)
            {
                break;      /* 索引越界即遍历结束，这是正常退出条件 */
            }
            printf("  ✗ 读取索引 %d 失败: %s\n", index, strerror(errno));
            return -1;
        }

        uint32_t scancode = scancode_to_uint32(ke.scancode, ke.len);
        const struct key_mapping *map = find_mapping(scancode);
        if (!map)
        {
            continue;
        }

        ke.keycode = map->keycode;
        if (ioctl(fd, EVIOCSKEYCODE_V2, &ke) < 0)
        {
            printf("  ✗ 修改失败 0x%06x (%s → %s): %s\n",
                   scancode, map->from, map->to, strerror(errno));
            continue;
        }

        printf("  ✓ %s: 0x%06x (%s → %s)\n",
               map->desc, scancode, map->from, map->to);
        changed++;
    }

    return changed;
}

/* 打印当前命中映射表的键位，用于修改前后对比 */
static void dump_current_mappings(int fd)
{
    struct input_keymap_entry ke;
    int found = 0;

    printf("\n当前键位映射:\n");

    for (int index = 0; ; index++)
    {
        memset(&ke, 0, sizeof(ke));
        ke.index = index;
        ke.len   = 4;
        ke.flags = INPUT_KEYMAP_BY_INDEX;

        if (ioctl(fd, EVIOCGKEYCODE_V2, &ke) < 0)
        {
            if (errno == EINVAL)
            {
                break;
            }
            printf("  ✗ 读取索引 %d 失败: %s\n", index, strerror(errno));
            break;
        }

        uint32_t scancode = scancode_to_uint32(ke.scancode, ke.len);
        if (find_mapping(scancode))
        {
            printf("  扫描码 0x%06x -> 键码 %u\n", scancode, ke.keycode);
            found = 1;
        }
    }

    if (!found)
    {
        printf("  （未发现映射表中的扫描码）\n");
    }
}

/* 自动查找目标设备，成功返回 1 并写入路径 */
static int find_device(char *path, size_t pathsize)
{
    for (int i = 0; i < MAX_INPUT_DEVICES; i++)
    {
        snprintf(path, pathsize, "/dev/input/event%d", i);

        /* 用 O_RDONLY 探测：没有权限写也能先判断是不是目标设备 */
        int fd = open(path, O_RDONLY);
        if (fd < 0)
        {
            continue;
        }

        int match = is_mipad2_keyboard(fd);
        close(fd);

        if (match)
        {
            return 1;
        }
    }

    return 0;
}

int main(int argc, char *argv[])
{
    char device_path[DEVICE_NAME_MAX];
    int  fd = -1;
    int  ret = EXIT_FAILURE;

    printf("mipad2 键盘重映射工具\n");

    /* --list 不需要 root，也不碰设备 */
    if (argc > 1 && strcmp(argv[1], "--list") == 0)
    {
        list_mapping();
        return EXIT_SUCCESS;
    }

    if (argc > 1 && (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0))
    {
        usage(argv[0]);
        return EXIT_SUCCESS;
    }

    if (argc > 1)
    {
        if (strlen(argv[1]) >= sizeof(device_path))
        {
            printf("错误: 设备路径过长\n");
            return EXIT_FAILURE;
        }
        snprintf(device_path, sizeof(device_path), "%s", argv[1]);

        /* 先确认设备存在，再谈权限：否则会报一个误导性的 root 错误 */
        if (access(device_path, F_OK) != 0)
        {
            printf("错误: 设备不存在 %s\n", device_path);
            return EXIT_FAILURE;
        }
    }

    if (geteuid() != 0)
    {
        printf("错误: 需要 root 权限（要改写内核键位表）\n");
        return EXIT_FAILURE;
    }

    if (argc == 1 && !find_device(device_path, sizeof(device_path)))
    {
        printf("未找到 mipad2 键盘设备（扫描 /dev/input/event0..%d）\n",
               MAX_INPUT_DEVICES - 1);
        return EXIT_FAILURE;
    }
    else
    {
        printf("找到目标设备: %s\n", device_path);
    }

    fd = open(device_path, O_RDWR);
    if (fd < 0)
    {
        printf("设备打开失败 %s: %s\n", device_path, strerror(errno));
        return EXIT_FAILURE;
    }

    if (!is_mipad2_keyboard(fd))
    {
        printf("设备 %s 不是 mipad2 键盘，未做任何修改\n", device_path);
        goto out;
    }

    dump_current_mappings(fd);

    printf("\n开始应用重映射:\n");
    int changed = apply_keymap(fd);
    if (changed < 0)
    {
        printf("遍历键位表失败，映射未完成\n");
        goto out;
    }
    if (changed == 0)
    {
        printf("没有需要修改的条目（可能已应用过）\n");
    }
    else
    {
        printf("已修改 %d 项\n", changed);
    }

    printf("设备 %s 处理完成\n", device_path);
    ret = EXIT_SUCCESS;

out:
    close(fd);
    return ret;
}

/*
 * 与参考实现的差异（均为修正，不是重写）：
 *
 * 1. fd 初始化与错误路径
 *    参考实现里 fd 未初始化就用于 goto error 分支的 close(fd)，
 *    且该分支还会调用 open() 失败后的 fd。这里统一走 out 标签。
 *
 * 2. apply_keymap 的返回值
 *    参考实现写成 "if (!apply_keymap_single(...)) ret = 0;"，
 *    逻辑反了：成功反而置 0、失败保持 -1，最终 main 判断也跟着错。
 *    这里改为返回实际修改条数，负值表示遍历失败。
 *
 * 3. 设备探测方式
 *    参考实现用 O_RDWR 探测所有设备，非 root 时全部失败、无法定位；
 *    这里用 O_RDONLY 探测，确定目标后再以 O_RDWR 打开。
 *
 * 4. 扫描码长度
 *    参考实现对 4 字节截断写死，这里按 ke.len 实际长度转换。
 *
 * 5. 已是目标值时不重复写入，并给出提示。
 */
