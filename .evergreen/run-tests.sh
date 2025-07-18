#!/bin/bash

set -o xtrace   # Write all commands first to stderr
set -o errexit  # Exit the script with error if any of the commands fail

# Supported/used environment variables:
#       MONGODB_URI             Set the suggested connection MONGODB_URI (including credentials and topology info)
#       RVM_RUBY                Define the Ruby version to test with, using its RVM identifier.
#                               For example: "ruby-3.0" or "jruby-9.2"

MRSS_ROOT=`dirname "$0"`/../spec/shared

. $MRSS_ROOT/shlib/distro.sh
. $MRSS_ROOT/shlib/set_env.sh
. $MRSS_ROOT/shlib/server.sh
. `dirname "$0"`/functions.sh

arch=`host_distro`

set_fcv
set_env_vars
set_env_python
set_env_ruby

if test -n "$APP_TESTS"; then
  set_env_node
fi

prepare_server $arch

install_mlaunch_venv

if test "$TOPOLOGY" = load-balanced; then
  install_haproxy
fi

# Launching mongod under $MONGO_ORCHESTRATION_HOME
# makes its log available through log collecting machinery

export dbdir="$MONGO_ORCHESTRATION_HOME"/db
mkdir -p "$dbdir"

calculate_server_args
launch_server "$dbdir"

uri_options="$URI_OPTIONS"

which bundle
bundle --version

if echo $RVM_RUBY |grep -q jruby && test "$DRIVER" = master-jruby; then
  # See https://jira.mongodb.org/browse/RUBY-2156
  git clone https://github.com/mongodb/bson-ruby
  (cd bson-ruby &&
    bundle install &&
    rake compile &&
    gem build *.gemspec &&
    gem install *.gem)
fi

git config --global --add safe.directory "*"

if test "$DRIVER" = "master"; then
  bundle install --gemfile=gemfiles/driver_master.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_master.gemfile
elif test "$DRIVER" = "stable"; then
  bundle install --gemfile=gemfiles/driver_stable.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_stable.gemfile
elif test "$DRIVER" = "oldstable"; then
  bundle install --gemfile=gemfiles/driver_oldstable.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_oldstable.gemfile
elif test "$DRIVER" = "min"; then
  bundle install --gemfile=gemfiles/driver_min.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_min.gemfile
elif test "$DRIVER" = "bson-min"; then
  bundle install --gemfile=gemfiles/bson_min.gemfile
  BUNDLE_GEMFILE=gemfiles/bson_min.gemfile
elif test "$DRIVER" = "bson-master"; then
  bundle install --gemfile=gemfiles/bson_master.gemfile
  BUNDLE_GEMFILE=gemfiles/bson_master.gemfile
elif test "$DRIVER" = "stable-jruby"; then
  bundle install --gemfile=gemfiles/driver_stable_jruby.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_stable_jruby.gemfile
elif test "$DRIVER" = "oldstable-jruby"; then
  bundle install --gemfile=gemfiles/driver_oldstable_jruby.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_oldstable_jruby.gemfile
elif test "$DRIVER" = "min-jruby"; then
  bundle install --gemfile=gemfiles/driver_min_jruby.gemfile
  BUNDLE_GEMFILE=gemfiles/driver_min_jruby.gemfile
elif test "$RAILS" = "master-jruby"; then
  bundle install --gemfile=gemfiles/rails-master_jruby.gemfile
  BUNDLE_GEMFILE=gemfiles/rails-master_jruby.gemfile
elif test -n "$RAILS" && test "$RAILS" != 6.1; then
  bundle install --gemfile=gemfiles/rails-"$RAILS".gemfile
  BUNDLE_GEMFILE=gemfiles/rails-"$RAILS".gemfile
else
  bundle install
fi

export BUNDLE_GEMFILE

if test "$TOPOLOGY" = "sharded-cluster"; then
  # We assume that sharded cluster has two mongoses
  export MONGODB_URI="mongodb://localhost:27017,localhost:27018/?appName=test-suite&$uri_options"
else
  export MONGODB_URI="mongodb://localhost:27017/?appName=test-suite&$uri_options"
fi

set +e
if test -n "$TEST_CMD"; then
  eval $TEST_CMD
elif test -n "$TEST_I18N_FALLBACKS"; then
  bundle exec rspec spec/integration/i18n_fallbacks_spec.rb spec/mongoid/criteria_spec.rb spec/mongoid/contextual/mongo_spec.rb
elif test -n "$APP_TESTS"; then
  if test -z "$DOCKER_PRELOAD"; then
    ./spec/shared/bin/install-node
  fi

  bundle exec rspec spec/integration/app_spec.rb
else
  bundle exec rake ci
fi

test_status=$?
echo "TEST STATUS: ${test_status}"
set -e

if test -f tmp/rspec-all.json; then
  mv tmp/rspec-all.json tmp/rspec.json
fi

python3 -m mtools.mlaunch.mlaunch stop --dir "$dbdir" || true

exit ${test_status}
