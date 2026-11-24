#include <nautilus-extension.h>

#define KWICK_TYPE_NEARBY (kwick_nearby_get_type())
G_DECLARE_FINAL_TYPE(KwickNearby, kwick_nearby, KWICK, NEARBY, GObject)

struct _KwickNearby
{
    GObject parent_instance;
};

static void kwick_nearby_menu_provider_init(NautilusMenuProviderInterface *iface);

G_DEFINE_DYNAMIC_TYPE_EXTENDED(KwickNearby, kwick_nearby, G_TYPE_OBJECT, G_TYPE_FLAG_FINAL,
                               G_IMPLEMENT_INTERFACE_DYNAMIC(NAUTILUS_TYPE_MENU_PROVIDER, kwick_nearby_menu_provider_init))

static void share_activate(NautilusMenuItem *item, gpointer user_data)
{
    GList *files = g_object_get_data(G_OBJECT(item), "kwick-files");
    GPtrArray *argv = g_ptr_array_new_with_free_func(g_free);
    g_ptr_array_add(argv, g_strdup("kwick-nearby"));
    g_ptr_array_add(argv, g_strdup("--share"));
    for (GList *l = files; l != NULL; l = l->next) {
        GFile *location = nautilus_file_info_get_location(NAUTILUS_FILE_INFO(l->data));
        char *path = location ? g_file_get_path(location) : NULL;
        if (path != NULL) {
            g_ptr_array_add(argv, path);
        }
        g_clear_object(&location);
    }
    g_ptr_array_add(argv, NULL);
    g_spawn_async(NULL, (char **)argv->pdata, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
    g_ptr_array_unref(argv);
}

static GList *get_file_items(NautilusMenuProvider *provider, GList *files)
{
    if (files == NULL) {
        return NULL;
    }
    for (GList *l = files; l != NULL; l = l->next) {
        GFile *location = nautilus_file_info_get_location(NAUTILUS_FILE_INFO(l->data));
        gboolean native = location != NULL && g_file_is_native(location);
        g_clear_object(&location);
        if (!native) {
            return NULL;
        }
    }
    NautilusMenuItem *item = nautilus_menu_item_new("KwickNearby::share", "Send Nearby…", "Send to a phone or computer nearby", "kwick-nearby");
    g_object_set_data_full(G_OBJECT(item), "kwick-files", nautilus_file_info_list_copy(files), (GDestroyNotify)nautilus_file_info_list_free);
    g_signal_connect(item, "activate", G_CALLBACK(share_activate), NULL);
    return g_list_append(NULL, item);
}

static void kwick_nearby_menu_provider_init(NautilusMenuProviderInterface *iface)
{
    iface->get_file_items = get_file_items;
}

static void kwick_nearby_init(KwickNearby *self)
{
}

static void kwick_nearby_class_init(KwickNearbyClass *klass)
{
}

static void kwick_nearby_class_finalize(KwickNearbyClass *klass)
{
}

static GType types[1];

G_MODULE_EXPORT void nautilus_module_initialize(GTypeModule *module)
{
    kwick_nearby_register_type(module);
    types[0] = KWICK_TYPE_NEARBY;
}

G_MODULE_EXPORT void nautilus_module_shutdown(void)
{
}

G_MODULE_EXPORT void nautilus_module_list_types(const GType **list, int *count)
{
    *list = types;
    *count = 1;
}
