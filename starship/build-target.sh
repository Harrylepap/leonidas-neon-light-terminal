#!/usr/bin/env bash
# Affiche la version CIBLE du build (java / node / php) lue dans les fichiers
# du projet — et non la version du runtime installe. Utilise par Starship
# via des modules [custom.*]. Sortie : la version seule, ou rien si introuvable.
# Usage : build-target.sh <java|node|php>

norm_java() {
    # 1.8 -> 8 ; 11 -> 11
    local v="$1"
    echo "${v#1.}"
}

clean_range() {
    # Retire les operateurs de plage : >=8.1 -> 8.1 ; ^18.0 -> 18.0
    local v="$1"
    echo "${v//[>=^~ ]/}"
}

case "${1:-}" in
    java)
        if [ -f pom.xml ]; then
            for prop in 'maven\.compiler\.release' 'maven\.compiler\.target' 'maven\.compiler\.source' 'java\.version'; do
                raw=$(grep -oE "<${prop}>[^<]+" pom.xml 2>/dev/null | head -1 | sed -E 's/.*>//')
                if [ -n "$raw" ]; then norm_java "$raw"; exit 0; fi
            done
        fi
        for f in build.gradle build.gradle.kts; do
            [ -f "$f" ] || continue
            line=$(grep -E 'sourceCompatibility|targetCompatibility|languageVersion|JavaVersion|<release>|[[:space:]]release' "$f" 2>/dev/null | head -1)
            [ -n "$line" ] || continue
            # Formes : VERSION_17 / JavaLanguageVersion.of(17) / = 11 / = '1.8'
            v=$(echo "$line" | grep -oE 'VERSION_[0-9]+' | grep -oE '[0-9]+' | head -1)
            [ -z "$v" ] && v=$(echo "$line" | grep -oE 'of\([0-9]+\)' | grep -oE '[0-9]+' | head -1)
            [ -z "$v" ] && v=$(echo "$line" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
            if [ -n "$v" ]; then norm_java "$v"; exit 0; fi
        done
        ;;
    node)
        if [ -f package.json ]; then
            raw=$(grep -oE '"node"[[:space:]]*:[[:space:]]*"[^"]+"' package.json 2>/dev/null \
                  | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/')
            raw=$(clean_range "$raw")
            if [ -n "$raw" ]; then echo "$raw"; exit 0; fi
        fi
        if [ -f .nvmrc ]; then
            tr -d ' \t\r\nv' < .nvmrc
        fi
        ;;
    php)
        if [ -f composer.json ]; then
            raw=$(grep -oE '"php"[[:space:]]*:[[:space:]]*"[^"]+"' composer.json 2>/dev/null \
                  | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/')
            raw=$(clean_range "$raw")
            if [ -n "$raw" ]; then echo "$raw"; exit 0; fi
        fi
        ;;
esac
