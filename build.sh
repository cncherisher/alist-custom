appName="alist"
builtAt="$(date +'%F %T %z')"
goVersion=$(go version | sed 's/go version //')
gitAuthor=$(git show -s --format='format:%aN <%ae>' HEAD)
gitCommit=$(git log --pretty=format:"%h" -1)

set -x
if [ "$1" = "dev" ]; then
  version="dev"
  webVersion="dev"
else
  version=$(git describe --abbrev=0 --tags)
  webVersion=$(wget -qO- -t1 -T2 "https://api.github.com/repos/alist-org/alist-web/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
fi

echo "build version: $gitTag"

ldflags="\
-w -s \
-X 'github.com/alist-org/alist/v3/internal/conf.BuiltAt=$builtAt' \
-X 'github.com/alist-org/alist/v3/internal/conf.GoVersion=$goVersion' \
-X 'github.com/alist-org/alist/v3/internal/conf.GitAuthor=$gitAuthor' \
-X 'github.com/alist-org/alist/v3/internal/conf.GitCommit=$gitCommit' \
-X 'github.com/alist-org/alist/v3/internal/conf.Version=$version' \
-X 'github.com/alist-org/alist/v3/internal/conf.WebVersion=$webVersion' \
"

FetchWebRelease() {
  rm -rf ./public/dist
  git clone https://github.com/cncherisher/alist-web.git alist-web --recursive 
  cd alist-web
  pnpm install && pnpm build
  mv -f dist ../public
  cd ..
}


BuildRelease() {
  echo -e "BuiltTime=$builtAt"
  echo -e "goVersion=$goVersion"
  echo -e "gitAuthor=$gitAuthor"
  echo -e "gitCommit=$gitCommit"
  rm -rf .git/
  mkdir -p "build"
  muslflags="--extldflags '-static -fpic' $ldflags"
  BASE="https://musl.sztu.ga/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross arm-linux-musleabihf-cross)
  for i in "${FILES[@]}"; do
    url="${BASE}${i}.tgz"
    axel -q -n 4 "${url}" -o "${i}.tgz"
    #curl -L -o "${i}.tgz" "${url}"
    sudo tar xf "${i}.tgz" --strip-components 1 -C /usr/local
  done
  OS_ARCHES=(linux-musl-amd64 linux-musl-arm64 linux-musl-arm)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc arm-linux-musleabihf-gcc)
  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    echo building for ${os_arch}
    export GOOS=${os_arch%%-*}
    export GOARCH=${os_arch##*-}
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter -v .
  done
  xgo -targets=linux/amd64,windows/amd64 -out "$appName" -ldflags="$ldflags" -tags=jsoniter -v .
  # why? Because some target platforms seem to have issues with upx compression
  upx -9 ./alist-linux-amd64
  upx -9 ./alist-windows*
  mv alist-* build
}

MakeRelease() {
  cd build
  mkdir compress
  for i in $(find . -type f -name "$appName-linux-*"); do
    cp "$i" alist
    tar -czvf compress/"$i".tar.gz alist
    rm -f alist
  done
  for i in $(find . -type f -name "$appName-windows-*"); do
    cp "$i" alist.exe
    zip compress/$(echo $i | sed 's/\.[^.]*$//').zip alist.exe
    rm -f alist.exe
  done
  cd compress
  find . -type f -print0 | xargs -0 md5sum >md5.txt
  cat md5.txt
  cd ../..
}

if [ "$1" = "release" ]; then
  FetchWebRelease
  BuildRelease
  MakeRelease
else
  echo -e "Parameter error"
fi
