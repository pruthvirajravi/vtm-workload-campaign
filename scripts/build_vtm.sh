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

# instrumentation patch (S1/S2/S3 streams) — optional until it lands
shopt -s nullglob
for p in ../patch/*.patch; do
  echo "applying $p"
  git apply --check "$p" && git apply "$p"
done

mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_COMPILER_LAUNCHER=ccache \
         -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
make -j "$JOBS" EncoderApp
ls -l source/App/EncoderApp/ || true
