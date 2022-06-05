#!/bin/sh
. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

LOG_FILE="/tmp/openclash.log"
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
dns_advanced_setting=$(uci -q get openclash.config.dns_advanced_setting)
core_type=$(uci -q get openclash.config.core_type)
enable_custom_dns=$(uci -q get openclash.config.enable_custom_dns)
append_wan_dns=$(uci -q get openclash.config.append_wan_dns || echo 1)
ipv6_dns=$(uci -q get openclash.config.ipv6_dns || echo 0)
tolerance=$(uci -q get openclash.config.tolerance || echo 0)
custom_fallback_filter=$(uci -q get openclash.config.custom_fallback_filter || echo 0)
enable_meta_core=$(uci -q get openclash.config.enable_meta_core || echo 0)

if [ -n "$(ruby_read "$5" "['tun']")" ]; then
   uci -q set openclash.config.config_reload=0
else
   if [ -n "${11}" ]; then
      uci -q set openclash.config.config_reload=0
   fi
fi

if [ -z "${11}" ]; then
   en_mode_tun=0
else
   en_mode_tun=${11}
fi

if [ -z "${12}" ]; then
   stack_type=system
else
   stack_type=${12}
fi

if [ "${22}" != "1" ]; then
   enable_geoip_dat="false"
else
   enable_geoip_dat="true"
fi

if [ "${26}" != "1" ]; then
   enable_tcp_concurrent="false"
else
   enable_tcp_concurrent="true"
fi

if [ "$(ruby_read "$5" "['external-controller']")" != "$controller_address:$3" ]; then
   uci -q set openclash.config.config_reload=0
fi
    
if [ "$(ruby_read "$5" "['secret']")" != "$2" ]; then
   uci -q set openclash.config.config_reload=0
fi

if [ "$core_type" != "TUN" ] && [ "${10}" == "script" ]; then
   rule_mode="rule"
   uci -q set openclash.config.proxy_mode="$rule_mode"
   uci -q set openclash.config.router_self_proxy="1"
   LOG_OUT "Warning: Only TUN Core Support Script Mode, Switch To The Rule Mode!"
else
   rule_mode="${10}"
fi

uci commit openclash

#获取认证信息
yml_auth_get()
{
   local section="$1"
   local enabled username password
   config_get_bool "enabled" "$section" "enabled" "1"
   config_get "username" "$section" "username" ""
   config_get "password" "$section" "password" ""

   if [ "$enabled" = "0" ]; then
      return
   fi

   if [ -z "$username" ] || [ -z "$password" ]; then
      return
   else
      echo "  - $username:$password" >>/tmp/yaml_openclash_auth
   fi
}

#添加自定义DNS设置
yml_dns_custom()
{
   if [ "$1" = 1 ] || [ "$3" = 1 ]; then
   	sys_dns_append "$3" "$4"
      config_load "openclash"
      config_foreach yml_dns_get "dns_servers"
   fi
}

#获取DHCP或接口的DNS并追加
sys_dns_append()
{
   if [ "$1" = 1 ]; then
   	wan_dns=$(/usr/share/openclash/openclash_get_network.lua "dns")
      wan6_dns=$(/usr/share/openclash/openclash_get_network.lua "dns6")
      wan_gate=$(/usr/share/openclash/openclash_get_network.lua "gateway")
      wan6_gate=$(/usr/share/openclash/openclash_get_network.lua "gateway6")
      dhcp_iface=$(/usr/share/openclash/openclash_get_network.lua "dhcp")
      pppoe_iface=$(/usr/share/openclash/openclash_get_network.lua "pppoe")
      if [ -z "$dhcp_iface" ] && [ -z "$pppoe_iface" ]; then
         if [ -n "$wan_dns" ]; then
            for i in $wan_dns; do
               echo "    - \"$i\"" >>/tmp/yaml_config.namedns.yaml
            done
         fi
         if [ -n "$wan6_dns" ] && [ "$2" = 1 ]; then
            for i in $wan6_dns; do
               echo "    - \"[${i}]:53\"" >>/tmp/yaml_config.namedns.yaml
            done
         fi
         if [ -n "$wan_gate" ]; then
            for i in $wan_gate; do
                echo "    - \"$i\"" >>/tmp/yaml_config.namedns.yaml
            done
         fi
         if [ -n "$wan6_gate" ] && [ "$2" = 1 ]; then
            for i in $wan6_gate; do
               echo "    - \"[${i}]:53\"" >>/tmp/yaml_config.namedns.yaml
            done
         fi
      else
         if [ -n "$dhcp_iface" ]; then
            for i in $dhcp_iface; do
               echo "    - dhcp://\"$i\"" >>/tmp/yaml_config.namedns.yaml
            done
            if [ -n "$wan_gate" ]; then
               for i in $wan_gate; do
                   echo "    - \"$i\"" >>/tmp/yaml_config.namedns.yaml
               done
            fi
            if [ -n "$wan6_gate" ] && [ "$2" = 1 ]; then
               for i in $wan6_gate; do
                  echo "    - \"[${i}]:53\"" >>/tmp/yaml_config.namedns.yaml
               done
            fi
         fi
         if [ -n "$pppoe_iface" ]; then
            if [ -n "$wan_dns" ]; then
		           for i in $wan_dns; do
		              echo "    - \"$i\"" >>/tmp/yaml_config.namedns.yaml
		           done
		       fi
		       if [ -n "$wan6_dns" ] && [ "$2" = 1 ]; then
		          for i in $wan6_dns; do
		             echo "    - \"[${i}]:53\"" >>/tmp/yaml_config.namedns.yaml
		          done
		       fi
         fi
      fi
      if [ -f "/tmp/yaml_config.namedns.yaml" ] && [ -z "$(grep "^ \{0,\}nameserver:$" /tmp/yaml_config.namedns.yaml 2>/dev/null)" ]; then
         sed -i '1i\  nameserver:'  "/tmp/yaml_config.namedns.yaml"
      fi
   fi
}

#获取自定义DNS设置
yml_dns_get()
{
   local section="$1" regex='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
   local enabled port type ip group dns_type dns_address interface specific_group
   config_get_bool "enabled" "$section" "enabled" "1"
   config_get "port" "$section" "port" ""
   config_get "type" "$section" "type" ""
   config_get "ip" "$section" "ip" ""
   config_get "group" "$section" "group" ""
   config_get "interface" "$section" "interface" ""
   config_get "specific_group" "$section" "specific_group" ""
   config_get_bool "node_resolve" "$section" "node_resolve" "0"

   if [ "$enabled" = "0" ]; then
      return
   fi

   if [ -z "$ip" ]; then
      return
   fi
   
   if [[ "$ip" =~ "$regex" ]]; then
      ip="[${ip}]"
   fi

   if [ "$type" = "tcp" ]; then
      dns_type="tcp://"
   elif [ "$type" = "tls" ]; then
      dns_type="tls://"
   elif [ "$type" = "udp" ]; then
      dns_type=""
   elif [ "$type" = "https" ]; then
      dns_type="https://"
   elif [ "$type" = "quic" ]; then
      dns_type="quic://"
   fi

   if [ -n "$port" ] && [ -n "$ip" ]; then
      dns_address="$ip:$port"
   elif [ -z "$port" ] && [ -n "$ip" ]; then
      dns_address="$ip"
   else
      return
   fi

   if [ "$type" == "quic" ] && [ "$enable_meta_core" != "1" ]; then
      LOG_OUT "Warning: Only Meta Core Support QUIC Type DNS, Skip【$dns_type$dns_address】"
      return
   fi

   if [ "$node_resolve" = "1" ] && [ "$enable_meta_core" = "1" ]; then
      if [ -z "$(grep "^ \{0,\}proxy-server-nameserver:$" /tmp/yaml_config.proxynamedns.yaml 2>/dev/null)" ]; then
         echo "  proxy-server-nameserver:" >/tmp/yaml_config.proxynamedns.yaml
      fi
      echo "    - \"$dns_type$dns_address\"" >>/tmp/yaml_config.proxynamedns.yaml
   elif [ "$node_resolve" = "1" ]; then
      LOG_OUT "Warning: Only Meta Core Support proxy-server-nameserver, Skip Setting【$dns_type$dns_address】"
   fi

   if [ "$specific_group" != "Disable" ] && [ "$enable_meta_core" = "1" ]; then
      specific_group="#$specific_group"
   elif [ "$specific_group" != "Disable" ]; then
      LOG_OUT "Warning: Only Meta Core Support Specific Group, Skip Setting【$dns_type$dns_address】"
      specific_group=""
   else
      specific_group=""
   fi

   if [ "$interface" != "Disable" ] && [ "$enable_meta_core" != "1" ]; then
      interface="#$interface"
   elif [ "$interface" != "Disable" ]; then
      LOG_OUT "Warning: Meta Core not Support Specific Interface, Skip Setting【$dns_type$dns_address】"
      interface=""
   else
      interface=""
   fi

   dns_address="$dns_address$interface$specific_group"

   if [ -n "$group" ]; then
      if [ "$group" = "nameserver" ]; then
         if [ -z "$(grep "^ \{0,\}nameserver:$" /tmp/yaml_config.namedns.yaml 2>/dev/null)" ]; then
            echo "  nameserver:" >/tmp/yaml_config.namedns.yaml
         fi
         echo "    - \"$dns_type$dns_address\"" >>/tmp/yaml_config.namedns.yaml
      else
         if [ -z "$(grep "^ \{0,\}fallback:$" /tmp/yaml_config.falldns.yaml 2>/dev/null)" ]; then
            echo "  fallback:" >/tmp/yaml_config.falldns.yaml
         fi
         echo "    - \"$dns_type$dns_address\"" >>/tmp/yaml_config.falldns.yaml
      fi
   else
      return
   fi
}

config_load "openclash"
config_foreach yml_auth_get "authentication"
yml_dns_custom "$enable_custom_dns" "$5" "$append_wan_dns" "${16}"

ruby -ryaml -E UTF-8 -e "
begin
   Value = YAML.load_file('$5');
rescue Exception => e
   puts '${LOGTIME} Error: Load File Failed,【' + e.message + '】'
end
#field name check
begin
Thread.new{
   if Value.key?('Proxy') or Value.key?('Proxy Group') or Value.key?('Rule') or Value.key?('rule-provider') then
      if Value.key?('Proxy') then
         Value['proxies'] = Value['Proxy']
         Value.delete('Proxy')
         puts '${LOGTIME} Warning: Proxy is no longer used. Auto replaced by proxies'
      end
      if Value.key?('Proxy Group') then
         Value['proxy-groups'] = Value['Proxy Group']
         Value.delete('Proxy Group')
         puts '${LOGTIME} Warning: Proxy Group is no longer used. Auto replaced by proxy-groups'
      end
      if Value.key?('Rule') then
         Value['rules'] = Value['Rule']
         Value.delete('Rule')
         puts '${LOGTIME} Warning: Rule is no longer used. Auto replaced by rules'
      end
      if Value.key?('rule-provider') then
         Value['rule-providers'] = Value['rule-provider']
         Value.delete('rule-provider')
         puts '${LOGTIME} Warning: rule-provider is no longer used. Auto replaced by rule-providers'
      end;
   end;
}.join;
end;
begin
Thread.new{
   Value['redir-port']=$4;
   Value['tproxy-port']=${15};
   Value['port']=$7;
   Value['socks-port']=$8;
   Value['mixed-port']=${14};
   Value['mode']='$rule_mode';
   Value['log-level']='$9';
   Value['allow-lan']=true;
   Value['external-controller']='0.0.0.0:$3';
   Value['secret']='$2';
   Value['bind-address']='*';
   Value['external-ui']='/usr/share/openclash/ui';
   if $6 == 1 then
      Value['ipv6']=true;
   else
      Value['ipv6']=false;
   end;
   if '${25}' != '0' then
      Value['interface-name']='${25}';
   else
      Value.delete('interface-name');
   end;
   if ${21} == 1 then
      Value['geodata-mode']=$enable_geoip_dat;
      Value['geodata-loader']='${23}';
      Value['tcp-concurrent']=$enable_tcp_concurrent;
   else
      if Value.key?('geodata-mode') then
         Value.delete('geodata-mode');
      end
      if Value.key?('geodata-loader') then
         Value.delete('geodata-loader');
      end
   end;
   if not Value.key?('dns') then
      Value_1={'dns'=>{'enable'=>true}};
      Value['dns']=Value_1['dns'];
   else
      Value['dns']['enable']=true;
   end;
   if ${16} == 1 then
      Value['dns']['ipv6']=true;
   else
      Value['dns']['ipv6']=false;
   end;
   if ${19} != 1 then
      Value['dns']['enhanced-mode']='$1';
   else
      Value['dns']['enhanced-mode']='fake-ip';
   end;
   if '$1' == 'fake-ip' or ${19} == 1 then
      Value['dns']['fake-ip-range']='198.18.0.1/16';
   else
      Value['dns'].delete('fake-ip-range');
   end;
   Value['dns']['listen']='0.0.0.0:${13}';
   #meta only
   if ${20} == 1 and ${21} == 1 then
      Value_sniffer={'sniffer'=>{'enable'=>true}};
      Value['sniffer']=Value_sniffer['sniffer'];
      Value_sniffer={'sniffing'=>['tls','http']};
      Value['sniffer'].merge!(Value_sniffer);
      if File::exist?('/etc/openclash/custom/openclash_force_sniffing_domain.yaml') and ${24} == 1 then
         Value_7 = YAML.load_file('/etc/openclash/custom/openclash_force_sniffing_domain.yaml');
         if Value_7 != false and not Value_7['force-domain'].to_a.empty? then
            Value['sniffer']['force-domain']=Value_7['force-domain'];
            Value['sniffer']['force-domain']=Value['sniffer']['force-domain'].uniq;
         end
      end;
      if File::exist?('/etc/openclash/custom/openclash_sniffing_domain_filter.yaml') and ${24} == 1 then
         Value_7 = YAML.load_file('/etc/openclash/custom/openclash_sniffing_domain_filter.yaml');
         if Value_7 != false and not Value_7['skip-sni'].to_a.empty? then
            Value['sniffer']['skip-domain']=Value_7['skip-sni'];
            Value['sniffer']['skip-domain']=Value['sniffer']['skip-domain'].uniq;
         end
         if Value_7 != false and not Value_7['skip-domain'].to_a.empty? then
            Value['sniffer']['skip-domain']=Value_7['skip-domain'];
            Value['sniffer']['skip-domain']=Value['sniffer']['skip-domain'].uniq;
         end
      end;
      if File::exist?('/etc/openclash/custom/openclash_sniffing_port_filter.yaml') and ${24} == 1 then
         Value_7 = YAML.load_file('/etc/openclash/custom/openclash_sniffing_port_filter.yaml');
         if Value_7 != false and not Value_7['port-whitelist'].to_a.empty? then
            Value['sniffer']['port-whitelist']=Value_7['port-whitelist'];
            Value['sniffer']['port-whitelist']=Value['sniffer']['port-whitelist'].uniq;
         end
      end;
   else
      if Value.key?('sniffer') then
         Value.delete('sniffer');
      end;
   end;
   Value_2={'tun'=>{'enable'=>true}};
   if $en_mode_tun != 0 then
      Value['tun']=Value_2['tun'];
      Value['tun']['stack']='$stack_type';
      if ${20} == 1 then
         Value['tun']['device']='utun';
      end;
      Value_2={'dns-hijack'=>['tcp://any:53']};
      Value['tun']['auto-route']=false;
      Value['tun']['auto-detect-interface']=false;
      Value['tun'].merge!(Value_2);
   else
      if Value.key?('tun') then
         Value.delete('tun');
      end;
   end;
   if Value.key?('iptables') then
      Value.delete('iptables');
   end;
   if not Value.key?('profile') then
      Value_3={'profile'=>{'store-selected'=>true}};
      Value['profile']=Value_3['profile'];
   else
      Value['profile']['store-selected']=true;
   end;
   if ${17} != 1 then
      Value['profile']['store-fake-ip']=false;
   else
      Value['profile']['store-fake-ip']=true;
   end;
   if Value.key?('ebpf') then
      Value.delete('ebpf');
   end;
   if Value.key?('routing-mark') then
      Value.delete('routing-mark');
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set General Failed,【' + e.message + '】';
end;

#auth
begin
Thread.new{
   if File::exist?('/tmp/yaml_openclash_auth') then
      Value_1 = YAML.load_file('/tmp/yaml_openclash_auth');
      Value['authentication']=Value_1
   elsif Value.key?('authentication') then
       Value.delete('authentication');
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set authentication Failed,【' + e.message + '】';
end;

#custom dns
begin
Thread.new{
   if '$enable_custom_dns' == '1' or '$append_wan_dns' == '1' then
      if File::exist?('/tmp/yaml_config.namedns.yaml') then
         Value_1 = YAML.load_file('/tmp/yaml_config.namedns.yaml');
         Value_1['nameserver'] = Value_1['nameserver'].uniq;
         Value['dns']['nameserver'] = Value_1['nameserver'];
         if File::exist?('/tmp/yaml_config.falldns.yaml') then
            Value_1 = YAML.load_file('/tmp/yaml_config.falldns.yaml');
            Value_1['fallback'] = Value_1['fallback'].uniq;
            Value['dns']['fallback'] = Value_1['fallback'];
         end;
      else
         puts '${LOGTIME} Error: Nameserver Option Must Be Setted, Stop Customing DNS Servers';
      end;
   end;
}.join;
end;

#proxy server dns
begin
Thread.new{
   if '$enable_custom_dns' == '1' then
      if File::exist?('/tmp/yaml_config.proxynamedns.yaml') then
         Value_1 = YAML.load_file('/tmp/yaml_config.proxynamedns.yaml');
         Value_1['proxy-server-nameserver'] = Value_1['proxy-server-nameserver'].uniq;
         Value['dns']['proxy-server-nameserver'] = Value_1['proxy-server-nameserver'];
      end;
   end;
}.join;
end;

begin
Thread.new{
   if '$tolerance' != '0' then
      Value['proxy-groups'].each{
         |x|
            if x['type'] == 'url-test' then
               x['tolerance']='${tolerance}';
            end
         };
   end;
}.join;
rescue Exception => e
	puts '${LOGTIME} Error: Set Url-Test Group Tolerance Failed,【' + e.message + '】';
end;

#custom hosts
begin
Thread.new{
   if File::exist?('/etc/openclash/custom/openclash_custom_hosts.list') then
      begin
         Value_3 = IO.readlines('/etc/openclash/custom/openclash_custom_hosts.list');
         if not Value_3.empty? then
            Value_3 = Value_3.map!{|x| x.gsub(/#.*$/,'').strip} - ['', nil];
            Value['dns']['use-hosts']=true;
            if Value.has_key?('hosts') and not Value['hosts'].to_a.empty? then
               Value_3.each{|x| Value['hosts'].merge!(x)};
            else
               Value_3.each{|x| Value['hosts'].merge!(x)};
            end;
            Value['hosts'].uniq;
         end;
         
      rescue
         Value_3 = YAML.load_file('/etc/openclash/custom/openclash_custom_hosts.list');
         if Value_3 != false then
            Value['dns']['use-hosts']=true;
            if Value.has_key?('hosts') and not Value['hosts'].to_a.empty? then
               Value['hosts'].merge!(Value_3);
            else
               Value['hosts']=Value_3;
            end;
            Value['hosts'].uniq;
         end;
      end;
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set Hosts Rules Failed,【' + e.message + '】';
end;

#fake-ip-filter
begin
Thread.new{
   if '$1' == 'fake-ip' then
      if File::exist?('/etc/openclash/custom/openclash_custom_fake_filter.list') then
         begin
            Value_4 = YAML.load_file('/etc/openclash/custom/openclash_custom_fake_filter.list');
            if Value_4 != false and not Value_4['fake-ip-filter'].to_a.empty? then
               if Value['dns'].has_key?('fake-ip-filter') and not Value['dns']['fake-ip-filter'].to_a.empty? then
                  Value['dns']['fake-ip-filter'] = Value['dns']['fake-ip-filter'] | Value_4;
               else
                  Value['dns']['fake-ip-filter'] = Value_4['fake-ip-filter'];
               end;
            end;
         rescue
            Value_4 = IO.readlines('/etc/openclash/custom/openclash_custom_fake_filter.list');
            if not Value_4.empty? then
               Value_4 = Value_4.map!{|x| x.gsub(/#.*$/,'').strip} - ['', nil];
               if Value['dns'].has_key?('fake-ip-filter') and not Value['dns']['fake-ip-filter'].to_a.empty? then
                  Value['dns']['fake-ip-filter'] = Value['dns']['fake-ip-filter'] | Value_4;
               else
                  Value['dns']['fake-ip-filter'] = Value_4;
               end;
            end;
         end;
      end;
      if ${18} == 1 then
         if Value['dns'].has_key?('fake-ip-filter') and not Value['dns']['fake-ip-filter'].to_a.empty? then
            Value['dns']['fake-ip-filter'].insert(-1,'+.nflxvideo.net');
            Value['dns']['fake-ip-filter'].insert(-1,'+.media.dssott.com');
            Value['dns']['fake-ip-filter']=Value['dns']['fake-ip-filter'].uniq;
         else
            Value['dns'].merge!({'fake-ip-filter'=>['+.nflxvideo.net', '+.media.dssott.com']});
         end;
      end;
   elsif ${19} == 1 then
      if Value['dns'].has_key?('fake-ip-filter') and not Value['dns']['fake-ip-filter'].to_a.empty? then
         Value['dns']['fake-ip-filter'].insert(-1,'+.*');
         Value['dns']['fake-ip-filter']=Value['dns']['fake-ip-filter'].uniq;
      else
         Value['dns'].merge!({'fake-ip-filter'=>['+.*']});
      end;
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set Fake-IP-Filter Failed,【' + e.message + '】';
end;

#nameserver-policy
begin
Thread.new{
   if '$dns_advanced_setting' == '1' then
      if File::exist?('/etc/openclash/custom/openclash_custom_domain_dns_policy.list') then
         Value_6 = YAML.load_file('/etc/openclash/custom/openclash_custom_domain_dns_policy.list');
         if Value_6 != false then
            if Value['dns'].has_key?('nameserver-policy') and not Value['dns']['nameserver-policy'].to_a.empty? then
               Value['dns']['nameserver-policy'].merge!(Value_6);
               Value['dns']['nameserver-policy'].uniq;
            else
               Value['dns']['nameserver-policy']=Value_6;
            end;
         end;
      end;
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set Nameserver-Policy Failed,【' + e.message + '】';
end;

#Vmess-ws formalt check, not support proxy-provider
begin
Thread.new{
   if Value.key?('proxies') then
      Value['proxies'].each{
      |x|
      if x['type'] != 'vmess' then
         next
      end;
      if x.key?('ws-path') then
         if not x.key?('ws-opts') then
            x['ws-opts'] = {'path'=>x['ws-path'].to_s};
         else
            if x['ws-opts'].nil? then
               x['ws-opts'] = {'path'=>x['ws-path'].to_s};
            elsif x['ws-opts']['path'].nil? then
               x['ws-opts'].update({'path'=>x['ws-path'].to_s});
            end
         end
         x.delete('ws-path');
      end;
      if x.key?('ws-headers') then
         x['ws-headers'].keys.each{
         |v|
            if not x.key?('ws-opts') then
               x['ws-opts'] = {'headers'=>{v.to_s=>x['ws-headers'][v].to_s}};
            else
               if x['ws-opts'].nil? then
                  x['ws-opts'] = {'headers'=>{v.to_s=>x['ws-headers'][v].to_s}};
               elsif x['ws-opts']['headers'].nil? then
                  x['ws-opts'].update({'headers'=>{v.to_s=>x['ws-headers'][v].to_s}});
               #elsif not x['ws-opts']['headers'].key?(v)
               #   x['ws-opts']['headers'].update({v.to_s=>x['ws-headers'][v].to_s});
               end;
            end;
         };
         x.delete('ws-headers');
      end;
      };
   end;
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Edit Vmess Compatible Failed,【' + e.message + '】';
end;

# dns check
begin
Thread.new{
   if not Value['dns'].key?('nameserver') or Value['dns']['nameserver'].to_a.empty? then
      puts '${LOGTIME} Detected That The nameserver DNS Option Has No Server Set, Starting To Complete...';
      Value_1={'nameserver'=>['114.114.114.114','119.29.29.29','223.5.5.5']};
      Value_2={'fallback'=>['https://dns.cloudflare.com/dns-query','https://public.dns.iij.jp/dns-query','https://jp.tiar.app/dns-query','https://jp.tiarap.org/dns-query']};
      Value['dns'].merge!(Value_1);
      Value['dns'].merge!(Value_2);
   end;
}.join;
end;

#fallback-filter
begin
Thread.new{
   if '$custom_fallback_filter' == '1' then
      if not Value['dns'].key?('fallback') then
         puts '${LOGTIME} Error: Fallback-Filter Need fallback of DNS Been Setted, Ignore...';
      elsif not YAML.load_file('/etc/openclash/custom/openclash_custom_fallback_filter.yaml') then
         puts '${LOGTIME} Error: Unable To Parse Custom Fallback-Filter File, Ignore...';
      else
         Value['dns']['fallback-filter'] = YAML.load_file('/etc/openclash/custom/openclash_custom_fallback_filter.yaml')['fallback-filter'];
      end;
   end;
}.join;
end;

#default-nameserver
begin
Thread.new{
   reg = /(^https:\/\/|^tls:\/\/|^quic:\/\/)?((\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.){3}(\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])(?::(?:[0-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?/;
   reg6 = /(^https:\/\/|^tls:\/\/|^quic:\/\/)?(?:(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}:[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){5}:([0-9A-Fa-f]{1,4}:)?[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){4}:([0-9A-Fa-f]{1,4}:){0,2}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){3}:([0-9A-Fa-f]{1,4}:){0,3}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){2}:([0-9A-Fa-f]{1,4}:){0,4}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(([0-9A-Fa-f]{1,4}:){0,5}:((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(::([0-9A-Fa-f]{1,4}:){0,5}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|([0-9A-Fa-f]{1,4}::([0-9A-Fa-f]{1,4}:){0,5}[0-9A-Fa-f]{1,4})|(::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){1,7}:))|\[(?:(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}:[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){5}:([0-9A-Fa-f]{1,4}:)?[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){4}:([0-9A-Fa-f]{1,4}:){0,2}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){3}:([0-9A-Fa-f]{1,4}:){0,3}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){2}:([0-9A-Fa-f]{1,4}:){0,4}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(([0-9A-Fa-f]{1,4}:){0,5}:((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(::([0-9A-Fa-f]{1,4}:){0,5}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|([0-9A-Fa-f]{1,4}::([0-9A-Fa-f]{1,4}:){0,5}[0-9A-Fa-f]{1,4})|(::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){1,7}:))\](?::(?:[0-9]|[1-9][0-9]{1,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?/i;
   if Value['dns'].has_key?('fallback') then
      Value_1=Value['dns']['nameserver'] | Value['dns']['fallback'];
   else
      Value_1=Value['dns']['nameserver'];
   end;
   Value_1.each{|x|
      if x =~ reg or x =~ reg6 then
         if Value['dns'].has_key?('default-nameserver') then
            Value['dns']['default-nameserver']=Value['dns']['default-nameserver'].to_a.insert(-1,x).uniq;
         else
            Value_2={'default-nameserver'=>[x]};
            Value['dns'].merge!(Value_2);
         end;
      end;
      };
}.join;
rescue Exception => e
   puts '${LOGTIME} Error: Set default-nameserver Failed,【' + e.message + '】';
ensure
   File.open('$5','w') {|f| YAML.dump(Value, f)};
end" 2>/dev/null >> $LOG_FILE
