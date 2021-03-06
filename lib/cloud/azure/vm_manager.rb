require 'common/common'
require 'time'
require 'socket'

require_relative 'dynamic_network'
require_relative 'vip_network'
require_relative 'helpers'

module Bosh::AzureCloud
  class VMManager

    include Helpers

    def initialize(vm_client, img_client, vnet_manager, storage_manager)
      @vm_manager = vm_client
      @img_client = img_client
      @vnet_manager = vnet_manager
      @storage_manager = storage_manager
    end

    # TODO: Need a better place to specify instance size than manifest azure properties section
    def create(uuid, stemcell, cloud_opts)
      # Include 25555 by default as it is the BOSH port
      endpoints = '25555:25555'

      params = {
          :vm_name => "vm-#{uuid}",
          :vm_user => cloud_opts['user'],
          # TODO: Password is temporary until I can upload private key file
          :password => 'P4$$w0rd!',
          :image => stemcell,
          :location => 'East US'

          # TODO: This doesnt work and is ignored... Need to research azure sdk and add functionality if necessary... REST API call is COMPLICATED!!!!
          #:reserved_ip_name => 'boshtest01'
      }

      opts = {
          # Storage account names must be between 3 and 24 characters in length and use numbers and lower-case letters only.
          # Error: ConflictError : The storage account named '' is already taken.
          # We probably should create one storage account per Azure account for all BOSH stuff...
          :storage_account_name => @storage_manager.create,
          :cloud_service_name => "cloud-service-#{uuid}",

          # TODO: Must figure a way to upload key to bosh
          #:private_key_file => cloud_opts['ssh_key_file'] || raise('ssh_key_path must be given to cloud_opts'),
          :certificate_file => cloud_opts['cert_file'] || raise('ssh_cert_path must be given to cloud_opts'),
          :vm_size => cloud_opts[:instance_size] || 'Small',
          :availability_set_name => "avail-set-#{uuid}"
      }

      if (!dynamic_network.nil?)
        # As far as I am aware, Azure only supports one virtual network for a vm and it's
        # indicated by name in the API, so I am accepting only the first key (the name of the network)
        opts[:virtual_network_name] = dynamic_network.name
        opts[:subnet_name] = dynamic_network.first_subnet[:name]
      end

      if (!vip_network.nil?)
        # VIP network just represents the dynamically assigned public ip address azure gives.
        # I am unaware of how to statically assign one
        vip_network.tcp_endpoints.each do |endpoint|
          # Prepend the endpoint followed by a comma
          endpoints = "#{endpoint}, #{endpoints}"
        end
      end

      opts[:tcp_endpoints] = endpoints

      # TODO: For some reason, this method sometimes returns the following string 'ConflictError : The specified DNS name is already taken.' if the given cloud service already exists...
      @vm_manager.create_virtual_machine(params, opts)
    end

    # TODO: Need to find vms with missing cloud service or with missing name
    def find(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_manager.get_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def delete(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_manager.delete_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def reboot(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_manager.restart_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def start(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_manager.start_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def shutdown(vm_id)
      vm_ext = vm_from_yaml(vm_id)
      @vm_manager.shutdown_virtual_machine(vm_ext[:vm_name], vm_ext[:cloud_service_name])
    end

    def instance_id
      hostname = `hostname -f`
      vm_id = { :vm_name => hostname.split('.')[0], :cloud_service_name => hostname.split('.')[1] }
      inst = find vm_id

      vm_to_yaml(inst)
    end

    def network_spec(vm_id)
      vm = find(vm_id) || raise('Given vm id does not exist')
      d_net = extract_dynamic_network vm
    end

    private

    def dynamic_network
      @vnet_manager.network
    end

    def vip_network
      @vnet_manager.vip_network
    end

    # TODO: Need to figure out how to recreate the 'vlan_name' part of the vip network
    # TODO: Need to return a VipNetwork object
    def extract_vip_network(vm)
      tcp = []
      vm.tcp_endpoints.each do |endpoint|
        next if (endpoint[:name].eql?('SSH')) # SSH is the auto-assigned ssh one from azure and we can ignore it
        tcp << "#{endpoint[:local_port]}:#{endpoint[:public_port]}"
      end
    end

    def extract_dynamic_network(vm)
      return nil if (vm.virtual_network_name.nil?)
      vnet = @vnet_manager.list_virtual_networks.select do |network|
        network.name.eql?(vm.virtual_network_name)
      end.first
      return nil if (vnet.nil?)
      DynamicNetwork.new(@vnet_manager, {
                                          'vlan_name' => vnet.name,
                                          'affinity_group' => vnet.affinity_group,
                                          'address_space' => vnet.address_space,
                                          'dns' => vnet.dns_servers,
                                          'subnets' => vnet.subnets.collect { |subnet|
                                            {
                                                'range' => subnet[:address_prefix],
                                                'name' => subnet[:name]
                                            }
                                        }
      })
    end

    def verify_stemcell(stemcell_id)
      is_in_canonical = @img_client.list_virtual_machine_images.any? do |image|
        image.name == stemcell_id
      end

    end

    def request_private_images
      uri = 'https://management.core.windows.net/e6621b72-cdf5-4557-a471-1102ddd62c06/services/vmimages'
      response = get(uri)
      xml = XmlSimple.xml_in(response.body)
      xml
    end
  end
end