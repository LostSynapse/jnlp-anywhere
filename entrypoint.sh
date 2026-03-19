#!/bin/bash
BOLD=$(tput bold 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

echo "${BOLD}${CYAN}jnlp-anywhere ${JNLP_ANYWHERE_VERSION} starting...${RESET}"

# Debug modes:
# XPRA_DEBUG=1 - Xpra verbose logging only
# XPRA_DEBUG=2 - Shell tracing + Xpra verbose logging
XPRA_LOG_OPTS=""
if [ "${XPRA_DEBUG}" = "3" ]; then
    set -x
    XPRA_LOG_OPTS="--debug all"
elif [ "${XPRA_DEBUG}" = "2" ]; then
    set -x
elif [ "${XPRA_DEBUG}" = "1" ]; then
    XPRA_LOG_OPTS="--debug all"
fi

set -e

# Validate required env var
if [ -z "${JNLP_URL}" ]; then
    echo "ERROR: JNLP_URL is required"
    exit 1
fi

# Fetch jnlp at runtime
echo "${BOLD}${CYAN}Fetching JNLP from ${JNLP_URL}...${RESET}"
mkdir -p /app
curl -s "${JNLP_URL}" -o /app/launch.jnlp

# Parse codebase and main class from jnlp
echo "${BOLD}${CYAN}Parsing JNLP...${RESET}"
CODEBASE=$(xmlstarlet sel -t -v "/jnlp/@codebase" /app/launch.jnlp)
MAIN_CLASS=$(xmlstarlet sel -t -v "//application-desc/@main-class" /app/launch.jnlp)

# Parse any JVM arguments from java-vm-args attribute
JVM_ARGS=$(xmlstarlet sel -t -v "//j2se/@java-vm-args" /app/launch.jnlp 2>/dev/null || true)

# Parse heap size attributes and convert to JVM flags if present
HEAP_INIT=$(xmlstarlet sel -t -v "//j2se/@initial-heap-size" /app/launch.jnlp 2>/dev/null || true)
HEAP_MAX=$(xmlstarlet sel -t -v "//j2se/@max-heap-size" /app/launch.jnlp 2>/dev/null || true)
[ -n "$HEAP_INIT" ] && JVM_ARGS="$JVM_ARGS -Xms${HEAP_INIT}"
[ -n "$HEAP_MAX" ] && JVM_ARGS="$JVM_ARGS -Xmx${HEAP_MAX}"

# Parse any application arguments
APP_ARGS=$(xmlstarlet sel -t -m "//application-desc/argument" -v "." -n \
    /app/launch.jnlp 2>/dev/null | tr '\n' ' ' || true)

# Download all jars
# ${jar#/} strips leading slash from href if present to avoid double-slash in URL
echo "${BOLD}${CYAN}Downloading jars...${RESET}"
xmlstarlet sel -t -v "//jar/@href" /app/launch.jnlp | while read jar; do
    echo "${BOLD}Fetching ${CODEBASE}/${jar#/}${RESET}" && \
    curl --progress-bar "${CODEBASE}/${jar#/}" -o "/app/$(basename ${jar})"
done

# Build classpath
CLASSPATH=$(find /app -iname "*.jar" | tr '\n' ':' | sed 's/:$//')

# Generate default-settings.txt for the HTML5 client at runtime.
# This file sets default values for the connect dialog.
# Generated fresh at every container start from environment variables.
SETTINGS_FILE=/usr/share/xpra/www/default-settings.txt
cat > "${SETTINGS_FILE}" << EOF
# jnlp-anywhere runtime-generated settings
# Generated at container start from environment variables
EOF

# Configure Xpra socket auth
AUTH_OPTS=""
if [ -n "${XPRA_PASSWORD}" ]; then
    echo -n "${XPRA_PASSWORD}" > /etc/xpra/password
    AUTH_OPTS=",auth=file,filename=/etc/xpra/password"
fi

# XPRA_AUDIO=true to enable pulseaudio (for JNLP apps that use audio)
AUDIO_OPTS="--pulseaudio=no --audio=no"
if [ "${XPRA_AUDIO}" = "true" ]; then
    AUDIO_OPTS=""
fi

# Preseed password into HTML5 client default-settings — explicit opt-in only.
# Requires both XPRA_PASSWORD and XPRA_PRESEED_PASSWORD=true.
# WARNING: If the port is also directly published, the password will be
# served to any browser that can reach it. Direct port exposure and preseed
# mode are mutually exclusive if access control matters. See documentation.
# NOTE: Whether preseed results in fully transparent auto-connect or merely
# pre-fills the password field requires verification against a live instance.
if [ -n "${XPRA_PASSWORD}" ] && [ "${XPRA_PRESEED_PASSWORD}" = "true" ]; then
    echo "password=${XPRA_PASSWORD}" >> "${SETTINGS_FILE}"
fi

# Create proper runtime directory for xpra-user
export XDG_RUNTIME_DIR=/tmp/runtime-1000
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Launch
echo "${BOLD}${CYAN}Starting Xpra...${RESET}"
exec xpra start :99 \
    --bind-tcp=0.0.0.0:14500${AUTH_OPTS} \
    --html=on \
    --no-daemon \
    --input-method=none \
    --xvfb="Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /dev/null -config /etc/xpra/xorg.conf" \
    --exit-with-children=yes \
    ${AUDIO_OPTS} \
    ${XPRA_LOG_OPTS} \
    --start-new-commands=no \
    --mmap=no \
    --webcam=no \
    --opengl=no \
    --printing=no \
    --mdns=no \
    --notifications=no \
    --bell=no \
    --start-child="java ${JVM_ARGS} -cp '${CLASSPATH}' ${MAIN_CLASS} ${APP_ARGS}"
