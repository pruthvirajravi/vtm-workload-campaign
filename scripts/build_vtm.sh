#!/usr/bin/env bash
# Build VTM at $VTM_TAG, applying the instrumentation patch if present.
set -euo pipefail
VTM_TAG="${VTM_TAG:?set VTM_TAG (must match the Phase-1 runs)}"
JOBS="${JOBS:-$(nproc)}"

if [ ! -d vtm ]; then
  git clone --depth 1 --branch "$VTM_TAG" \
    https://vcgit.hhi.fraunhofer.de/jvet/VVCSoftware_VTM.git vtm
fi
cd vtm

# instrumentation patch (S1/S2/S3 streams) - optional until it lands
shopt -s nullglob
for p in ../patch/*.patch; do
  echo "applying $p"
  git apply --check "$p" && git apply "$p"
done

# --- toolchain compatibility, BUILD SYSTEM ONLY (encoder source untouched) --
# 1) old VTM tags predate GCC 13 ('uint32_t does not name a type'):
#    prefer g++-12 and force-include <cstdint>.
# 2) VTM sets -Werror; newer compilers emit warnings VTM never saw
#    (array comparison, address-never-null). Strip -Werror from the cmake
#    build config so warnings stay warnings.
grep -rl -- "-Werror" CMakeLists.txt cmake 2>/dev/null | xargs -r sed -i 's/-Werror//g'

CCBIN="${CCBIN:-$(command -v gcc-12 || command -v gcc)}"
CXXBIN="${CXXBIN:-$(command -v g++-12 || command -v g++)}"
echo "compiler: $CXXBIN"

mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_COMPILER="$CCBIN" -DCMAKE_CXX_COMPILER="$CXXBIN" \
         -DCMAKE_C_COMPILER_LAUNCHER=ccache \
         -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
         -DCMAKE_CXX_FLAGS="-include cstdint" \
         -DCMAKE_C_FLAGS="-include stdint.h"
make -j "$JOBS" EncoderApp
ls -l source/App/EncoderApp/ || true
