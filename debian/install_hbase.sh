#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

usage() {
  echo "
usage: $0 <options>
  Required not-so-options:
     --build-dir=DIR             path to hbase dist.dir
     --prefix=PREFIX             path to install into
     --extra-dir=DIR             path to Bigtop distribution files

  Optional options:
     --doc-dir=DIR               path to install docs into [/usr/share/doc/hbase]
     --lib-dir=DIR               path to install hbase home [/usr/lib/hbase]
     --installed-lib-dir=DIR     path where lib-dir will end up on target system
     --bin-dir=DIR               path to install bins [/usr/bin]
     --examples-dir=DIR          path to install examples [doc-dir/examples]
     ... [ see source for more similar options ]
  "
  exit 1
}

OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'prefix:' \
  -l 'doc-dir:' \
  -l 'lib-dir:' \
  -l 'installed-lib-dir:' \
  -l 'bin-dir:' \
  -l 'examples-dir:' \
  -l 'conf-dir:' \
  -l 'extra-dir:' \
  -l 'build-dir:' -- "$@")

if [ $? != 0 ] ; then
    usage
fi

eval set -- "$OPTS"
while true ; do
    case "$1" in
        --prefix)
        PREFIX=$2 ; shift 2
        ;;
        --build-dir)
        BUILD_DIR=$2 ; shift 2
        ;;
        --doc-dir)
        DOC_DIR=$2 ; shift 2
        ;;
        --lib-dir)
        LIB_DIR=$2 ; shift 2
        ;;
        --installed-lib-dir)
        INSTALLED_LIB_DIR=$2 ; shift 2
        ;;
        --bin-dir)
        BIN_DIR=$2 ; shift 2
        ;;
        --examples-dir)
        EXAMPLES_DIR=$2 ; shift 2
        ;;
        --conf-dir)
        CONF_DIR=$2 ; shift 2
        ;;
        --extra-dir)
        EXTRA_DIR=$2 ; shift 2
        ;;
        --)
        shift ; break
        ;;
        *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

for var in PREFIX BUILD_DIR ; do
  if [ -z "$(eval "echo \$$var")" ]; then
    echo Missing param: $var
    usage
  fi
done

. ${EXTRA_DIR}/packaging_functions.sh

MAN_DIR=${MAN_DIR:-/usr/share/man/man1}
DOC_DIR=${DOC_DIR:-/usr/share/doc/hbase}
LIB_DIR=${LIB_DIR:-/usr/lib/hbase}
BIN_DIR=${BIN_DIR:-/usr/lib/hbase/bin}
ETC_DIR=${ETC_DIR:-/etc/hbase}
CONF_DIR=${CONF_DIR:-${ETC_DIR}/conf.dist}
THRIFT_DIR=${THRIFT_DIR:-${LIB_DIR}/include/thrift}

install -d -m 0755 $PREFIX/$LIB_DIR
install -d -m 0755 $PREFIX/$LIB_DIR/lib
install -d -m 0755 $PREFIX/$DOC_DIR
install -d -m 0755 $PREFIX/$BIN_DIR
install -d -m 0755 $PREFIX/$ETC_DIR
install -d -m 0755 $PREFIX/$MAN_DIR
install -d -m 0755 $PREFIX/$THRIFT_DIR

cp -ra $BUILD_DIR/lib/* ${PREFIX}/${LIB_DIR}/lib/

# Make HBase JARs findable from both pre- and post-0.96 locations
for lib in $PREFIX/$LIB_DIR/lib/hbase*.jar; do
    ln -s lib/`basename $lib` $PREFIX/$LIB_DIR/
done

cp -a $BUILD_DIR/docs/* $PREFIX/$DOC_DIR
cp $BUILD_DIR/*.txt $PREFIX/$DOC_DIR/
cp -a $BUILD_DIR/hbase-webapps $PREFIX/$LIB_DIR

cp -a $BUILD_DIR/conf $PREFIX/$CONF_DIR
cp -a $BUILD_DIR/bin/* $PREFIX/$BIN_DIR
# Purge scripts that don't work with packages
for file in rolling-restart.sh graceful_stop.sh local-regionservers.sh \
            master-backup.sh regionservers.sh zookeepers.sh hbase-daemons.sh \
            start-hbase.sh stop-hbase.sh local-master-backup.sh ; do
  rm -f $PREFIX/$BIN_DIR/$file
done

## hack -- tarball must be missing the thrift files
# cp $BUILD_DIR/hbase-thrift/src/main/resources/org/apache/hadoop/hbase/thrift/Hbase.thrift $PREFIX/$THRIFT_DIR/hbase1.thrift
# cp $BUILD_DIR/hbase-thrift/src/main/resources/org/apache/hadoop/hbase/thrift2/hbase.thrift $PREFIX/$THRIFT_DIR/hbase2.thrift

ln -s $ETC_DIR/conf $PREFIX/$LIB_DIR/conf

wrapper=$PREFIX/usr/bin/hbase
mkdir -p `dirname $wrapper`
cat > $wrapper <<'EOF'
#!/bin/bash

BIGTOP_DEFAULTS_DIR=${BIGTOP_DEFAULTS_DIR-/etc/default}
[ -n "${BIGTOP_DEFAULTS_DIR}" -a -r ${BIGTOP_DEFAULTS_DIR}/hbase ] && . ${BIGTOP_DEFAULTS_DIR}/hbase

# Autodetect JAVA_HOME if not defined
. /usr/lib/bigtop-utils/bigtop-detect-javahome

ALL_PARAMS="$@"

export HADOOP_CONF=${HADOOP_CONF:-/etc/hadoop/conf}
export HADOOP_HOME=${HADOOP_HOME:-/usr/lib/hadoop}
export ZOOKEEPER_HOME=${ZOOKEEPER_HOME:-/usr/lib/zookeeper}
export HBASE_CLASSPATH=$HADOOP_CONF:$HADOOP_HOME/*:$HADOOP_HOME/lib/*:$ZOOKEEPER_HOME/*:$ZOOKEEPER_HOME/lib/*:$HBASE_CLASSPATH

exec /usr/lib/hbase/bin/hbase $ALL_PARAMS

EOF
chmod 755 $wrapper

install -d -m 0755 $PREFIX/usr/bin

cp ${BUILD_DIR}/LICENSE.txt ${BUILD_DIR}/NOTICE.txt ${PREFIX}/${LIB_DIR}/

# Cloudera specific
install -d -m 0755 $PREFIX/$LIB_DIR/cloudera
cp cloudera/cdh_version.properties $PREFIX/$LIB_DIR/cloudera/

internal_versionless_symlinks ${PREFIX}/${LIB_DIR}/hbase*.jar
external_versionless_symlinks 'hbase' ${PREFIX}/${LIB_DIR}/lib

# The Hive packaging looks in the HBase lib directory for this jar when constructing its own
# local install. To simplify that process it needs a jar w/o a verison in the name.
# We have to make this link relative so that it'll still point at the correct place regardless of
# relocation e.g. with a parcel
# See CDH-16433
# This is a function so we can scope our variables.
# @param lib_dir the location of HBase's libarary files
function install_hbase_link_htrace_for_hive {
  declare lib_dir=$1
  declare f
  declare old_jar

  # HBase in C6 uses htrace v4, so we'll defensively try to avoid HTrace v3 jars.
  # First look for the jar in the client-facing area introduced by HBASE-20615
  for f in "${lib_dir}"/lib/client-facing-thirdparty/htrace-core4*.jar; do
    if [ -f "${f}" ]; then
      old_jar="client-facing-thirdparty/$(basename "${f}")"
      break;
    fi
  done
  # Iff we didn't find the htrace jar, look for the old location
  if [ -z "${old_jar}" ]; then
    for f in "${lib_dir}"/lib/htrace-core4*.jar; do
      if [ -f "${f}" ]; then
        old_jar="$(basename "${f}")"
        break;
      fi
    done
  fi
  if [ -z "${old_jar}" ]; then
    echo "Couldn't find HBase's copy of the core HTrace jar." >&2
    return 1
  fi
  # Create a versionless symlink for htrace-core.jar
  ln -s "${old_jar}" "${lib_dir}/lib/htrace-core.jar"
}

install_hbase_link_htrace_for_hive "${PREFIX}/${LIB_DIR}"
