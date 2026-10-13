#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-environment.sh"
select_architecture "$(uname -m)"

required_commands=(
    jq stat ps du mktemp find awk grep sed sysctl sw_vers date
    rustc cargo swift xcodebuild uname wc tr cat sleep
)
missing_commands=()
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing_commands+=("$command_name")
    fi
done
if (( ${#missing_commands[@]} > 0 )); then
    printf 'Missing required commands: %s\n' "${missing_commands[*]}" >&2
    exit 2
fi
JQ_VERSION="$(jq --version)"

build_rust
invalidate_swift_link .build/swift-linked-rust
swift build "${SWIFT_OPTIONS[@]}"
BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"

OUTPUT="$PROJECT_ROOT/.build/engine-evidence/index-resources"
mkdir -p "$OUTPUT"
rm -f "$OUTPUT/report.json" "$OUTPUT/report.md" "$OUTPUT/idle-unsettled.json"
mkdir -p "$PROJECT_ROOT/.build/index-resources"
WORKSPACE="$(mktemp -d "$PROJECT_ROOT/.build/index-resources/run-XXXXXX")"
IDLE_PID=""
cleanup() {
    if [[ -n "$IDLE_PID" ]]; then
        kill "$IDLE_PID" 2>/dev/null || true
        wait "$IDLE_PID" 2>/dev/null || true
    fi
    # Only this run's mktemp corpus, index and intermediate files are removed.
    rm -rf "$WORKSPACE"
}
trap cleanup EXIT

FILE_COUNT="${FSEARCH_RESOURCE_FILE_COUNT:-20000}"
FILE_BYTES="${FSEARCH_RESOURCE_FILE_BYTES:-512}"
IDLE_SECONDS="${FSEARCH_RESOURCE_IDLE_SECONDS:-60}"
IDLE_SETTLE_SECONDS="${FSEARCH_RESOURCE_IDLE_SETTLE_SECONDS:-180}"
WARM_RUNS="${FSEARCH_RESOURCE_WARM_RUNS:-5}"
if (( FILE_COUNT < 1 || FILE_BYTES < 64 || IDLE_SECONDS < 1 ||
      IDLE_SETTLE_SECONDS < 1 || WARM_RUNS < 1 )); then
    echo "Resource sizes must be positive (file bytes >= 64)" >&2
    exit 2
fi
export FSEARCH_RESOURCE_IDLE_SETTLE_SECONDS="$IDLE_SETTLE_SECONDS"

FIXTURES="$WORKSPACE/fixtures"
INDEX="$WORKSPACE/index"
mkdir -p "$FIXTURES" "$INDEX"
printf 'must be unreadable\n' > "$WORKSPACE/confinement-denied.txt"

for ((i = 1; i <= FILE_COUNT; i++)); do
    bucket=$(((i - 1) / 200))
    bucket_dir="$FIXTURES/bucket-$(printf '%04d' "$bucket")"
    if (( (i - 1) % 200 == 0 )); then
        mkdir -p "$bucket_dir"
    fi
    line="$(printf 'resource-content-token %06d' "$i")"
    padding=$((FILE_BYTES - ${#line} - 1))
    spaces="$(printf '%*s' "$padding" '')"
    printf '%s\n%s' "$line" "${spaces// /x}" > "$bucket_dir/resource-$i.txt"
done

find "$FIXTURES" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {print sum + 0}' > "$WORKSPACE/corpus-bytes"
CORPUS_BYTES="$(cat "$WORKSPACE/corpus-bytes")"
CORPUS_FILES="$(find "$FIXTURES" -type f | wc -l | tr -d ' ')"
CORPUS_DU_KB="$(du -sk "$FIXTURES" | awk '{print $1}')"

"$BIN_PATH/FsearchResourceCheck" synthetic "$FIXTURES" "$WORKSPACE/synthetic.json" \
    > "$WORKSPACE/synthetic.log" 2>&1

"$BIN_PATH/FsearchResourceCheck" build "$WORKSPACE" "$WORKSPACE/build.json" \
    > "$WORKSPACE/build.log" 2>&1

INDEX_DU_KB="$(du -sk "$INDEX" | awk '{print $1}')"
INDEX_FILES_JSON="$(
    find "$INDEX" -type f -exec stat -f '%N%t%z' {} + |
        awk -F '\t' '{printf "%s\t%s\n", $1, $2}' |
        jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], bytes: (.[1] | tonumber)})'
)"

IDLE_LOG="$WORKSPACE/idle.log"
"$BIN_PATH/FsearchResourceCheck" idle "$WORKSPACE" "$IDLE_SECONDS" "$WORKSPACE/idle.json" \
    > "$IDLE_LOG" 2>&1 &
IDLE_PID=$!
IDLE_STATE=""
MAX_IDLE_READY_POLLS=$(((IDLE_SETTLE_SECONDS + 300) * 10))
for ((i = 0; i < MAX_IDLE_READY_POLLS; i++)); do
    if grep -q '^IDLE_READY ' "$IDLE_LOG" 2>/dev/null; then
        IDLE_STATE="ready"
        break
    fi
    if grep -q '^IDLE_UNSETTLED ' "$IDLE_LOG" 2>/dev/null; then
        IDLE_STATE="unsettled"
        break
    fi
    if ! kill -0 "$IDLE_PID" 2>/dev/null; then
        IDLE_STATE="exited"
        break
    fi
    sleep 0.1
done
if [[ "$IDLE_STATE" != "ready" ]]; then
    echo "Idle phase did not reach a settled state: $IDLE_STATE" >&2
    cat "$IDLE_LOG" >&2 || true
    wait "$IDLE_PID" 2>/dev/null || true
    IDLE_PID=""
    if [[ -f "$WORKSPACE/idle.json" ]]; then
        cp "$WORKSPACE/idle.json" "$OUTPUT/idle-unsettled.json"
    fi
    exit 1
fi

: > "$WORKSPACE/idle-samples.tsv"
for ((elapsed = 0; elapsed < IDLE_SECONDS; elapsed++)); do
    if ! kill -0 "$IDLE_PID" 2>/dev/null; then
        break
    fi
    cpu_rss="$(
        ps -o %cpu=,rss= -p "$IDLE_PID" 2>/dev/null |
            awk 'NF == 2 {print $1 "\t" $2}' ||
            true
    )"
    threads="$(
        ps -M -p "$IDLE_PID" 2>/dev/null |
            awk 'NR > 1 {count += 1} END {print count + 0}' ||
            true
    )"
    if [[ -n "$cpu_rss" && -n "$threads" ]]; then
        printf '%s\t%s\n' "$cpu_rss" "$threads" >> "$WORKSPACE/idle-samples.tsv"
    fi
    sleep 1
done
wait "$IDLE_PID"
IDLE_PID=""

read -r IDLE_CPU_MEAN IDLE_CPU_PEAK IDLE_RSS_MEAN_KB IDLE_RSS_PEAK_KB IDLE_THREAD_MEAN IDLE_THREAD_PEAK < <(
    awk -F '\t' '
        {cpu += $1; if ($1 > cpu_peak) cpu_peak = $1;
         rss += $2; if ($2 > rss_peak) rss_peak = $2;
         threads += $3; if ($3 > thread_peak) thread_peak = $3; n += 1}
        END {
            if (n == 0) print "null null null null null null";
            else printf "%.2f %.2f %.2f %d %.2f %d\n",
                cpu / n, cpu_peak, rss / n, rss_peak, threads / n, thread_peak
        }
    ' "$WORKSPACE/idle-samples.tsv"
)
IDLE_SAMPLE_COUNT="$(wc -l < "$WORKSPACE/idle-samples.tsv" | tr -d ' ')"

DEVICE_MODEL="$(sysctl -n hw.model 2>/dev/null || true)"
CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
CPU_COUNT="$(sysctl -n hw.ncpu 2>/dev/null || true)"
PHYSICAL_MEMORY="$(sysctl -n hw.memsize 2>/dev/null || true)"
[[ -n "$DEVICE_MODEL" ]] || DEVICE_MODEL="unavailable"
[[ -n "$CPU_MODEL" ]] || CPU_MODEL="$(uname -p)"
[[ -n "$CPU_COUNT" ]] || CPU_COUNT="unavailable"
[[ -n "$PHYSICAL_MEMORY" ]] || PHYSICAL_MEMORY="unavailable"
OS_NAME="$(sw_vers -productName 2>/dev/null || echo macOS)"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || uname -r)"
OS_BUILD="$(sw_vers -buildVersion 2>/dev/null || echo unavailable)"
ARCHITECTURE="$(uname -m)"
RUST_VERSION="$(rustc --version 2>&1)"
CARGO_VERSION="$(cargo --version 2>&1)"
SWIFT_VERSION="$(swift --version 2>&1 | awk 'NR == 1 {print}')"
XCODE_VERSION="$(xcodebuild -version 2>&1 | awk 'NR <= 2 {printf "%s%s", separator, $0; separator="; "}')"
UPSTREAM_COMMIT="$(
    awk 'match($0, /rev = "[^"]+"/) {
        print substr($0, RSTART + 7, RLENGTH - 8)
        exit
    }' "$PROJECT_ROOT/bridge/Cargo.toml"
)"
GENERATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

jq -n \
    --arg generatedAt "$GENERATED_AT" \
    --arg deviceModel "$DEVICE_MODEL" \
    --arg cpuModel "$CPU_MODEL" \
    --arg architecture "$ARCHITECTURE" \
    --arg cpuCount "$CPU_COUNT" \
    --arg physicalMemoryBytes "$PHYSICAL_MEMORY" \
    --arg osName "$OS_NAME" \
    --arg osVersion "$OS_VERSION" \
    --arg osBuild "$OS_BUILD" \
    --arg rustVersion "$RUST_VERSION" \
    --arg cargoVersion "$CARGO_VERSION" \
    --arg swiftVersion "$SWIFT_VERSION" \
    --arg xcodeVersion "$XCODE_VERSION" \
    --arg jqVersion "$JQ_VERSION" \
    --arg upstreamCommit "$UPSTREAM_COMMIT" \
    --arg corpusPath "$FIXTURES" \
    --argjson corpusFiles "$CORPUS_FILES" \
    --argjson corpusBytes "$CORPUS_BYTES" \
    --argjson corpusDuKilobytes "$CORPUS_DU_KB" \
    --argjson indexDuKilobytes "$INDEX_DU_KB" \
    --arg indexDirectory "$INDEX" \
    --argjson indexFiles "$INDEX_FILES_JSON" \
    --arg syntheticCommand "$BIN_PATH/FsearchResourceCheck synthetic $FIXTURES $WORKSPACE/synthetic.json" \
    --arg buildCommand "$BIN_PATH/FsearchResourceCheck build $WORKSPACE $WORKSPACE/build.json" \
    --arg idleCommand "$BIN_PATH/FsearchResourceCheck idle $WORKSPACE $IDLE_SECONDS $WORKSPACE/idle.json" \
    --argjson idleSampleCount "$IDLE_SAMPLE_COUNT" \
    --argjson idleCpuMean "$IDLE_CPU_MEAN" \
    --argjson idleCpuPeak "$IDLE_CPU_PEAK" \
    --argjson idleRSSMeanKb "$IDLE_RSS_MEAN_KB" \
    --argjson idleRSSPeakKb "$IDLE_RSS_PEAK_KB" \
    --argjson idleThreadMean "$IDLE_THREAD_MEAN" \
    --argjson idleThreadPeak "$IDLE_THREAD_PEAK" \
    --slurpfile synthetic "$WORKSPACE/synthetic.json" \
    --slurpfile build "$WORKSPACE/build.json" \
    --slurpfile idle "$WORKSPACE/idle.json" \
    '{
        schemaVersion: 1,
        generatedAt: $generatedAt,
        environment: {
            deviceModel: $deviceModel,
            cpu: $cpuModel,
            cpuCount: ($cpuCount | if . == "unavailable" then null else tonumber end),
            physicalMemoryBytes: ($physicalMemoryBytes | if . == "unavailable" then null else tonumber end),
            architecture: $architecture,
            os: $osName,
            osVersion: $osVersion,
            osBuild: $osBuild,
            rust: $rustVersion,
            cargo: $cargoVersion,
            swift: $swiftVersion,
            xcode: $xcodeVersion,
            jq: $jqVersion,
            upstreamCommit: $upstreamCommit
        },
        corpus: {
            path: $corpusPath,
            fileCount: $corpusFiles,
            totalBytes: $corpusBytes,
            duKilobytes: $corpusDuKilobytes
        },
        commands: [
            {phase: "script", command: "bash scripts/index-resources.sh"},
            {phase: "synthetic", command: $syntheticCommand},
            {phase: "build", command: $buildCommand},
            {phase: "idle", command: $idleCommand}
        ],
        phases: {
            synthetic: $synthetic[0],
            build: ($build[0] + {
                indexDiskUsage: {
                    duKilobytes: $indexDuKilobytes,
                    directory: $indexDirectory,
                    files: $indexFiles
                }
            }),
            idle: ($idle[0] + {
                externalSamples: {
                    sampleCount: $idleSampleCount,
                    cpuPercentMean: $idleCpuMean,
                    cpuPercentPeak: $idleCpuPeak,
                    rssMeanKilobytes: $idleRSSMeanKb,
                    rssPeakKilobytes: $idleRSSPeakKb,
                    threadsMean: $idleThreadMean,
                    threadsPeak: $idleThreadPeak,
                    unavailable: (
                        if $idleSampleCount == 0
                        then {externalSampling: "The idle process exited before an external ps sample was captured."}
                        else {}
                        end
                    )
                }
            })
        },
        limitations: [
            "This report is a controlled-corpus result on the current device, not a client performance guarantee.",
            "A real user home, a formally signed app, iCloud behavior, Intel Macs and macOS 13 remain unverified.",
            "v0.1 name-only UI still permits background content indexing of eligible text under the confined test root.",
            "Content coverage is bounded by upstream extension, ignore, size and fallback-scan rules; it is not whole-disk full-text search."
        ]
    }' > "$OUTPUT/report.json"

jq -e '.phases.synthetic.isDefaultIndexCost == false and
       .phases.synthetic.isClientPerformanceGuarantee == false and
       .phases.build.usesDefaultEngineIndexing == true and
       .phases.build.contentSettle.timedOut == false and
       .phases.idle.contentSettled == true and
       .phases.idle.queriedDuringIdle == false and
       .phases.idle.savedDuringIdle == false and
       .phases.idle.externalSamples.sampleCount > 0' "$OUTPUT/report.json" > /dev/null

SYNTHETIC_QUERY_COUNT="$(jq -r '.phases.synthetic.queryCount' "$OUTPUT/report.json")"
SYNTHETIC_COLD_P50="$(jq -r '.phases.synthetic.cold.p50Seconds' "$OUTPUT/report.json")"
SYNTHETIC_COLD_P95="$(jq -r '.phases.synthetic.cold.p95Seconds' "$OUTPUT/report.json")"
SYNTHETIC_WARM_P50="$(jq -r '.phases.synthetic.warm.p50Seconds' "$OUTPUT/report.json")"
SYNTHETIC_WARM_P95="$(jq -r '.phases.synthetic.warm.p95Seconds' "$OUTPUT/report.json")"
BUILD_READY_SECONDS="$(jq -r '.phases.build.readyAfterSeconds' "$OUTPUT/report.json")"
BUILD_SETTLE_SECONDS="$(jq -r '.phases.build.contentSettle.waitedSeconds' "$OUTPUT/report.json")"
BUILD_CONTENT_TIMED_OUT="$(jq -r '.phases.build.contentSettle.timedOut' "$OUTPUT/report.json")"
BUILD_PEAK_RSS_BYTES="$(jq -r '.phases.build.peakRSSBytes' "$OUTPUT/report.json")"
BUILD_STATUS_READY="$(jq -c '.phases.build.statusAtReady' "$OUTPUT/report.json")"
BUILD_STATUS_SETTLED="$(jq -c '.phases.build.contentSettle.status' "$OUTPUT/report.json")"
BUILD_WARM_QUERY_COUNT="$(jq -r '.phases.build.warmQueryCount' "$OUTPUT/report.json")"
BUILD_WARM_P50="$(jq -r '.phases.build.warm.p50Seconds' "$OUTPUT/report.json")"
BUILD_WARM_P95="$(jq -r '.phases.build.warm.p95Seconds' "$OUTPUT/report.json")"
IDLE_CONTENT_SETTLED="$(jq -r '.phases.idle.contentSettled' "$OUTPUT/report.json")"
IDLE_SETTLE_TIMEOUT_SECONDS="$(jq -r '.phases.idle.settleTimeoutSeconds' "$OUTPUT/report.json")"
IDLE_SETTLE_WAITED_SECONDS="$(jq -r '.phases.idle.settleWaitedSeconds' "$OUTPUT/report.json")"
IDLE_STATUS_AT_SETTLE="$(jq -c '.phases.idle.statusAfterSettle' "$OUTPUT/report.json")"
IDLE_STATUS="$(jq -c '.phases.idle.statusAfterIdle' "$OUTPUT/report.json")"

cat > "$OUTPUT/report.md" <<EOF
# Fsearch 默认索引资源报告

生成时间：$GENERATED_AT

## 结论口径

本报告是当前设备、受控项目内语料上的结果，不是客户端性能保证。合成样本查询、真实受限首次扫描和空闲资源分别记录，不能把一个阶段的数字外推到另一个阶段。

## 环境与规模

| 项 | 值 |
| --- | --- |
| 设备 | $DEVICE_MODEL |
| CPU | $CPU_MODEL |
| CPU 数 | $CPU_COUNT |
| 架构 | $ARCHITECTURE |
| OS | $OS_NAME $OS_VERSION ($OS_BUILD) |
| Rust | $RUST_VERSION |
| Cargo | $CARGO_VERSION |
| Swift | $SWIFT_VERSION |
| Xcode | $XCODE_VERSION |
| jq | $JQ_VERSION |
| 上游 commit | $UPSTREAM_COMMIT |
| 语料文件数 | $CORPUS_FILES |
| 语料字节数 | $CORPUS_BYTES |
| 语料 du | $CORPUS_DU_KB KiB |
| 索引 du | $INDEX_DU_KB KiB |

## 命令

\`\`\`bash
bash scripts/index-resources.sh
$BIN_PATH/FsearchResourceCheck synthetic $FIXTURES $WORKSPACE/synthetic.json
$BIN_PATH/FsearchResourceCheck build $WORKSPACE $WORKSPACE/build.json
$BIN_PATH/FsearchResourceCheck idle $WORKSPACE $IDLE_SECONDS $WORKSPACE/idle.json
\`\`\`

## 第一段：合成样本查询

样本服务只扫描显式语料并建立内存样本索引，不启动真实 Engine，也不代表默认索引成本。查询执行 $SYNTHETIC_QUERY_COUNT 次；冷 p50/p95 为 $SYNTHETIC_COLD_P50 / $SYNTHETIC_COLD_P95 秒，热 p50/p95 为 $SYNTHETIC_WARM_P50 / $SYNTHETIC_WARM_P95 秒。结果数按每次查询保存在 \`report.json\`，不得把其中任一条上游 top-k 数字解释为客户端保证。

## 第二段：真实受限 Engine 首次扫描

独立进程启动 T07 受限 Engine，fixture 与索引分离，索引位于项目内临时 workspace。到 \`status.ready\` 用时 $BUILD_READY_SECONDS 秒。ready 状态：

\`\`\`json
$BUILD_STATUS_READY
\`\`\`

内容状态等待 $BUILD_SETTLE_SECONDS 秒，超时标记为 ${BUILD_CONTENT_TIMED_OUT}；等待条件为 \`contentPending == 0 and contentDocs > 0\`。等待结束状态：

\`\`\`json
$BUILD_STATUS_SETTLED
\`\`\`

进程峰值 RSS 为 $BUILD_PEAK_RSS_BYTES 字节，来自进程内 \`getrusage(RUSAGE_SELF).ru_maxrss\`，与 \`/usr/bin/time -l\` 同类口径。索引目录 du 为 $INDEX_DU_KB KiB，内部文件及字节数见 \`report.json\` 的 \`indexDiskUsage\`。ready 后执行 $BUILD_WARM_QUERY_COUNT 次有限 warm 查询，p50/p95 为 $BUILD_WARM_P50 / $BUILD_WARM_P95 秒；随后请求 \`saveIndex\` 并等待保存窗口，公开 API 不提供保存完成信号。

## 第三段：已有索引空闲

另一个独立进程在已有索引上启动 Engine。ready 后继续等待 \`contentDocs > 0 && contentPending == 0\`，上限 $IDLE_SETTLE_TIMEOUT_SECONDS 秒，实际等待 $IDLE_SETTLE_WAITED_SECONDS 秒，\`contentSettled=$IDLE_CONTENT_SETTLED\`。只有收敛后才输出 \`IDLE_READY\` 并开始采样；期间不查询、不保存，保持 $IDLE_SECONDS 秒。收敛状态：

\`\`\`json
$IDLE_STATUS_AT_SETTLE
\`\`\`

外部 \`ps\` 采样 $IDLE_SAMPLE_COUNT 次：CPU 均值/峰值为 $IDLE_CPU_MEAN / $IDLE_CPU_PEAK %，RSS 均值/峰值为 $IDLE_RSS_MEAN_KB / $IDLE_RSS_PEAK_KB KiB，线程均值/峰值为 $IDLE_THREAD_MEAN / ${IDLE_THREAD_PEAK}。结束状态：

\`\`\`json
$IDLE_STATUS
\`\`\`

## v0.1 内容读取与覆盖边界

v0.1 只有名称搜索入口，但保留上游默认机制时，后台仍可能读取符合规则的文本文件以维护内容索引。当前上游内容索引以 \`\$HOME\` 为初始范围，非 Git 仓库普通文本通常上限 1 MiB，无扩展名文本上限 256 KiB；Git 仓库多数文本最高约 10 MiB，但 JSON/JSONL/NDJSON 仍为 1 MiB。PDF、Word、Excel、PowerPoint、压缩包、图片等不做正文解码或 OCR。依赖、缓存、app/library bundle、部分 home 子目录、ignore 规则、生成文件与 minified/bundle 资产会排除；未覆盖范围回退扫描最多读取 200,000 个候选且单文件最多 1 MiB，因此不是全盘全文或无漏检保证。

## 未验证门禁

- 真实用户全盘 home 的初建耗时、索引体积、峰值 RSS 和空闲成本未在本报告验证。
- 正式签名应用的 TCC/FDA 覆盖、撤销和重启行为未验证。
- iCloud 占位文件、外接卷、Intel Mac 实机和 macOS 13 实机未验证。
- 本报告不构成 v0.1 客户端性能、覆盖完整性或内容索引完成时间保证。

## 上游方案判断

若维护者认为当前初建、峰值内存或空闲 CPU 不可接受，应优先推动上游增加公开的索引根目录、内容索引开关/预算、暂停/取消或进度与完成信号；不得通过复制内核、隐藏结果上限或把样本查询当保证来规避。本报告只提供决策证据，不替维护者作出保留或修改上游默认机制的决定。
EOF

printf 'Resource report: %s\n' "$OUTPUT/report.md"
