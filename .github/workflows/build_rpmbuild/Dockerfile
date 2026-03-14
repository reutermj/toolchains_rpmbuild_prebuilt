FROM ubuntu:latest

# ===========
# || Setup ||
# ===========
ENV SCRIPTS_DIR="/tmp/scripts"
ENV UTILS_DIR="/tmp/scripts"

COPY .github/workflows/utils/initialize_user $UTILS_DIR/
RUN $UTILS_DIR/initialize_user

USER builder
WORKDIR /home/builder

COPY .github/workflows/build_rpmbuild/environment $SCRIPTS_DIR/
COPY .github/workflows/utils/download_tarball $UTILS_DIR/

# =========================
# || Install Dependencies ||
# =========================
COPY .github/workflows/build_rpmbuild/step-01_install_dependencies $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-01_install_dependencies

COPY .github/workflows/utils/install_gh_cli $UTILS_DIR/
RUN $UTILS_DIR/install_gh_cli

# ========================
# || Download Sources   ||
# ========================
ARG GH_TOKEN

ARG ZLIB_VERSION=1.3.2
COPY .github/workflows/build_rpmbuild/step-02.01_download_zlib_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.01_download_zlib_source

ARG BZIP2_VERSION=1.0.8
COPY .github/workflows/build_rpmbuild/step-02.02_download_bzip2_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.02_download_bzip2_source

ARG XZ_VERSION=5.8.2
COPY .github/workflows/build_rpmbuild/step-02.03_download_xz_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.03_download_xz_source

ARG ZSTD_VERSION=1.5.7
COPY .github/workflows/build_rpmbuild/step-02.04_download_zstd_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.04_download_zstd_source

ARG OPENSSL_VERSION=3.6.1
COPY .github/workflows/build_rpmbuild/step-02.05_download_openssl_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.05_download_openssl_source

ARG SQLITE_VERSION=3510300
COPY .github/workflows/build_rpmbuild/step-02.06_download_sqlite_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.06_download_sqlite_source

ARG FILE_VERSION=5.47
COPY .github/workflows/build_rpmbuild/step-02.07_download_file_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.07_download_file_source

ARG POPT_VERSION=1.19
COPY .github/workflows/build_rpmbuild/step-02.08_download_popt_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.08_download_popt_source

ARG LUA_VERSION=5.4.7
COPY .github/workflows/build_rpmbuild/step-02.09_download_lua_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.09_download_lua_source

ARG LIBARCHIVE_VERSION=3.8.6
COPY .github/workflows/build_rpmbuild/step-02.10_download_libarchive_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.10_download_libarchive_source

ARG RPM_VERSION=6.0.1
COPY .github/workflows/build_rpmbuild/step-02.11_download_rpm_source $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-02.11_download_rpm_source

# =============================
# || Build Static Libraries  ||
# =============================
COPY .github/workflows/build_rpmbuild/step-03.01_build_zlib $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.01_build_zlib

COPY .github/workflows/build_rpmbuild/step-03.02_build_bzip2 $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.02_build_bzip2

COPY .github/workflows/build_rpmbuild/step-03.03_build_xz $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.03_build_xz

COPY .github/workflows/build_rpmbuild/step-03.04_build_zstd $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.04_build_zstd

COPY .github/workflows/build_rpmbuild/step-03.05_build_openssl $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.05_build_openssl

COPY .github/workflows/build_rpmbuild/step-03.06_build_sqlite $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.06_build_sqlite

COPY .github/workflows/build_rpmbuild/step-03.07_build_file $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.07_build_file

COPY .github/workflows/build_rpmbuild/step-03.08_build_popt $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.08_build_popt

COPY .github/workflows/build_rpmbuild/step-03.09_build_lua $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.09_build_lua

COPY .github/workflows/build_rpmbuild/step-03.10_build_libarchive $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-03.10_build_libarchive

# ======================
# || Build RPM        ||
# ======================
COPY .github/workflows/build_rpmbuild/step-04_build_rpm $SCRIPTS_DIR/
COPY .github/workflows/build_rpmbuild/patches $SCRIPTS_DIR/patches
RUN $SCRIPTS_DIR/step-04_build_rpm

COPY .github/workflows/build_rpmbuild/step-04.1_collect_licenses $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-04.1_collect_licenses

COPY .github/workflows/build_rpmbuild/step-05_package $SCRIPTS_DIR/
RUN $SCRIPTS_DIR/step-05_package

CMD ["/bin/bash"]
