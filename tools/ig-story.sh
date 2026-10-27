#!/usr/bin/env bash
# Publica una historia en Instagram. Entorno: IG_TOKEN, IG_USER, IMAGE_URL y, opcionalmente, VIDEO_URL.
# Con VIDEO_URL se publica como vídeo (dura lo que dura el vídeo); si Instagram lo rechaza, se publica la imagen fija (5 s).
set -uo pipefail
if [ -z "${IG_TOKEN:-}" ]; then echo "::error::Falta IG_ACCESS_TOKEN"; exit 1; fi
IG_TOKEN=$(printf %s "$IG_TOKEN" | tr -d "[:space:]\"'")
case "$IG_TOKEN" in IG*) API="https://graph.instagram.com/v21.0";; *) API="https://graph.facebook.com/v21.0";; esac
safe() { sed "s/$IG_TOKEN/***/g"; }
create() { # $1 = video|image
  local RES
  if [ "$1" = "video" ]; then RES=$(curl -sS -X POST "$API/$IG_USER/media" --data-urlencode "media_type=STORIES" --data-urlencode "video_url=$VIDEO_URL" --data-urlencode "access_token=$IG_TOKEN")
  else RES=$(curl -sS -X POST "$API/$IG_USER/media" --data-urlencode "media_type=STORIES" --data-urlencode "image_url=$IMAGE_URL" --data-urlencode "access_token=$IG_TOKEN"); fi
  ID=$(echo "$RES" | jq -r '.id // empty')
  if [ -z "$ID" ]; then echo "::warning::No se creó el contenedor ($1): $(echo "$RES" | jq -c '.error // .' | safe)"; return 1; fi
  local ST=""
  for i in $(seq 1 60); do
    ST=$(curl -sS "$API/$ID?fields=status_code&access_token=$IG_TOKEN" | jq -r '.status_code // "?"'); echo "estado ($1): $ST"
    [ "$ST" = "FINISHED" ] && return 0
    [ "$ST" = "ERROR" ] && { echo "::warning::Instagram rechazó el contenido ($1): $(curl -sS "$API/$ID?fields=status_code,status&access_token=$IG_TOKEN" | safe)"; return 1; }
    sleep 5
  done
  echo "::warning::Tiempo agotado esperando a Instagram ($1)"; return 1
}
MODE=image
if [ -z "${VIDEO_URL:-}" ]; then echo "::warning::No hay URL de vídeo: se publica la imagen"; fi
VIDEO_OK=0
if [ -n "${VIDEO_URL:-}" ]; then
  for TRY in 1 2 3; do
    if create video; then VIDEO_OK=1; break; fi
    echo "::warning::Intento $TRY de 3 con el vídeo fallido"; sleep 45
  done
fi
if [ "$VIDEO_OK" = "1" ]; then MODE=video
else
  IMG_OK=0
  for TRY in 1 2 3; do
    if create image; then IMG_OK=1; break; fi
    echo "::warning::Intento $TRY de 3 con la imagen fallido"; sleep 30
  done
  [ "$IMG_OK" = "1" ] || { echo "::error::No se pudo preparar la historia"; exit 1; }
  MODE=image
fi
if [ "${IG_NO_PUBLISH:-}" = "true" ]; then echo "::warning::PRUEBA sin publicar: modo=$MODE, video_url=${VIDEO_URL:-vacía}"; exit 0; fi
for TRY in 1 2 3 4; do
  OUT=$(curl -sS -X POST "$API/$IG_USER/media_publish" --data-urlencode "creation_id=$ID" --data-urlencode "access_token=$IG_TOKEN")
  if echo "$OUT" | jq -e '.id' >/dev/null; then echo "::notice::Historia publicada ($MODE): $(echo "$OUT" | jq -r .id)"; exit 0; fi
  echo "::warning::Publicación, intento $TRY de 4: $(echo "$OUT" | jq -c '.error // .' | safe)"
  sleep 30
done
echo "::error::Fallo al publicar: $(echo "$OUT" | jq -c '.error // .' | safe)"; exit 1
