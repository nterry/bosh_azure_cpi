module Bosh
  module AzureCloud; end
end

require 'httpclient'
require 'pp'
require 'set'
require 'tmpdir'
require 'securerandom'
require 'yajl'

require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'

require 'bosh/registry/client'

require 'cloud'
require 'cloud/azure/helpers'
require 'cloud/azure/cloud'
require 'cloud/azure/version'

require 'cloud/azure/network'
require 'cloud/azure/dynamic_network'
require 'cloud/azure/stemcell_manager'
require 'cloud/azure/virtual_network_manager'
require 'cloud/azure/vm_manager'

module Bosh
  module Clouds
    Azure = Bosh::AzureCloud::Cloud
  end
end