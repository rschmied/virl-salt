{% set ospassword = salt['pillar.get']('virl:password', salt['grains.get']('password', 'password')) %}
{% set openvpn_enable = salt['pillar.get']('virl:openvpn_enable', salt['grains.get']('openvpn_enable', False)) %}
{% set public_port = salt['pillar.get']('virl:public_port', salt['grains.get']('public_port', 'eth0')) %}

{% set l2_address = salt['pillar.get']('virl:l2_address', salt['grains.get']('l2_address', '172.16.1.254/24' )).split('/')[0] %}
{% set l2_cidr_network = salt['pillar.get']('virl:l2_network', salt['grains.get']('l2_network', '172.16.1.0/24' )) %}
{% set l2_network = l2_cidr_network.split('/')[0] %}
{% set l2_mask = salt['pillar.get']('virl:l2_mask', salt['grains.get']('l2_mask', '255.255.255.0' )) %}

{% set l2_address2 = salt['pillar.get']('virl:l2_address2', salt['grains.get']('l2_address2', '172.16.2.254/24' )).split('/')[0] %}
{% set l2_cidr_network2 = salt['pillar.get']('virl:l2_network2', salt['grains.get']('l2_network2', '172.16.2.0/24' )) %}
{% set l2_network2 = l2_cidr_network2.split('/')[0] %}
{% set l2_mask2 = salt['pillar.get']('virl:l2_mask2', salt['grains.get']('l2_mask2', '255.255.255.0' )) %}

{% set l3_address = salt['pillar.get']('virl:l3_address', salt['grains.get']('l3_address', '172.16.3.254/24' )).split('/')[0] %}
{% set l3_cidr_network = salt['pillar.get']('virl:l3_network', salt['grains.get']('l3_network', '172.16.3.0/24' )) %}
{% set l3_network = l3_cidr_network.split('/')[0] %}
{% set l3_mask = salt['pillar.get']('virl:l3_mask', salt['grains.get']('l3_mask', '255.255.255.0' )) %}

{% if openvpn_enable %}

vpn maximize:
  cmd.run:
    - names:
      - crudini --set /etc/virl.ini DEFAULT l2_network_gateway {{l2_address}}
      - crudini --set /etc/virl.ini DEFAULT l2_network_gateway2 {{l2_address2}}
      - crudini --set /etc/virl.ini DEFAULT l3_network_gateway {{l3_address}}
      - crudini --set /etc/virl/virl.cfg env virl_local_ip {{l2_address}}
      - crudini --set /etc/nova/nova.conf serial_console proxyclient_address {{l2_address}}
      - crudini --set /etc/nova/nova.conf DEFAULT serial_port_proxyclient_address {{l2_address}}
      - neutron --os-tenant-name admin --os-username admin --os-password {{ ospassword }} --os-auth-url=http://127.0.1.1:5000/v2.0 subnet-update flat --gateway_ip {{l2_address}}
      - neutron --os-tenant-name admin --os-username admin --os-password {{ ospassword }} --os-auth-url=http://127.0.1.1:5000/v2.0 subnet-update flat1 --gateway_ip {{l2_address2}}
      - neutron --os-tenant-name admin --os-username admin --os-password {{ ospassword }} --os-auth-url=http://127.0.1.1:5000/v2.0 subnet-update ext-net --gateway_ip {{l3_address}}

ufw accepted ports:
  cmd.run:
    - unless: "/usr/sbin/ufw status | grep 1194/tcp"
    - names:
      - ufw allow in on {{ public_port }} to any port 22 proto tcp
      - ufw allow in on {{ public_port }} to any port 443 proto tcp
      - ufw allow in on {{ public_port }} to any port 4505 proto tcp
      - ufw allow in on {{ public_port }} to any port 4506 proto tcp      
      - ufw allow in on {{ public_port }} to any port 1194 proto tcp
      - ufw allow from 10.0.0.0/8

ufw deny {{ public_port }}:
  cmd.run:
    - require:
      - cmd: ufw accepted ports
    - name: ufw deny in on {{ public_port }} to any

ufw accept all:
  cmd.run:
    - require:
      - cmd: ufw deny {{ public_port }}
    - names: 
      - ufw allow from any to any
      - ufw default allow routed


adding local route to openvpn:
  file.append:
    - name: /etc/openvpn/server.conf
    - text: |
        push "route {{l2_network2}} {{l2_mask2}} {{l2_address}}"
        push "route {{l3_network}} {{l3_mask}} {{l2_address}}"

adding nat to ufw:
  file.prepend:
    - name: /etc/ufw/before.rules
    - text:  |
        *nat
        :POSTROUTING ACCEPT [0:0]
        # translate outbound traffic from internal networks
        -A POSTROUTING -s {{l2_cidr_network}} -o {{ public_port }} -j MASQUERADE
        -A POSTROUTING -s {{l2_cidr_network2}} -o {{ public_port }} -j MASQUERADE
        -A POSTROUTING -s {{l3_cidr_network}} -o {{ public_port }} -j MASQUERADE
        # don't delete the 'COMMIT' line or these nat table rules won't
        # be processed
        COMMIT

ufw force enable:
  cmd.run:
    - order: last
    - names:
      - service neutron-l3-agent restart
      - service nova-serialproxy restart
      - service virl-std restart
      - service virl-uwm restart
      - service openvpn restart
      - ufw --force enable
      - ufw status verbose

{% endif %}
