new bool:__SPR_UseExternalFunction = false;
new String:__SPR_WeightFunctionName[128];
new String:__SPR_WeightPluginName[128];

// don't include function code in the library-plugin
#if !defined SPR_LIBRARY_VERSION

public SPR_RegisterWeightFunction(String:function_name[]) {
    if (__SPR_UseExternalFunction) {
        LogError("[SPR] Warning: RegisterWeightFunction called twice, %s replaced with %s",
                 __SPR_WeightFunctionName, function_name);
    }

    decl String:plugin_name[128];
    GetPluginFilename(INVALID_HANDLE, plugin_name, sizeof(plugin_name));

    if (strlen(function_name) >= sizeof(__SPR_WeightFunctionName)) {
        LogError("[SPR] Weight function name too long: %s", function_name);
        __SPR_UseExternalFunction = false;

    } else if (strlen(plugin_name) >= sizeof(__SPR_WeightPluginName)) {
        LogError("[SPR] Weight plugin name too long: %s", function_name);
        __SPR_UseExternalFunction = false;

    } else {
        strcopy(__SPR_WeightFunctionName, sizeof(__SPR_WeightFunctionName), function_name);
        strcopy(__SPR_WeightPluginName, sizeof(__SPR_WeightPluginName), plugin_name);
        __SPR_UseExternalFunction = true;
    }
}

#endif
