# Brotli assigns an absolute install name before creating these libraries.
cmake_language(DEFER CALL set_target_properties brotlicommon brotlidec brotlienc
    PROPERTIES INSTALL_NAME_DIR "@rpath")
