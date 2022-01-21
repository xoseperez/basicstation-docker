# LoRa Basics™ Station using balena.io with sx1301, sx1302 and sx1303 LoRa concentrators

This project deploys a LoRaWAN gateway with Basics™ Station Packet Forward protocol using Docker or Balena.io. It runs on a Raspberry Pi 3/4, Compute Module 3/4 or balenaFin with sx1301, sx1302 or sx1303 LoRa concentrators (e.g. RAK831, RAK833, RAK2245, RAK2247, RAK2287, RAK5146, Seeed WM1302 and IMST iC880a among others).


## Introduction

Deploy a LoRaWAN gateway running the Basics™ Station Semtech Packet Forward protocol in a docker container inside your Raspberry Pi or compatible SBC. Also, you can use balena.io and RAK to reduce friction for the LoRa gateway fleet owners. 

The Basics™ Station protocol enables the LoRa gateways with a reliable and secure communication between the gateways and the cloud and it is becoming the standard Packet Forward protocol used by most of the LoRaWAN operators.

This project has been tested with The Things Stack Community Edition (TTSCE or TTNv3).


## Requirements


### Hardware

* Raspberry Pi 3/4 or [balenaFin](https://www.balena.io/fin/)
* SD card in case of the RPi 3/4


#### LoRa Concentrators (SPI)

> Disclaimer: At the moment the basicstation project is not compatible with USB LoRa concentrators. Contributions are welcome :)

Supported LoRa concentrators:

* SX1301 
  * [IMST iC880a](https://shop.imst.de/wireless-modules/lora-products/8/ic880a-spi-lorawan-concentrator-868-mhz)
  * [RAK 831 Concentrator](https://store.rakwireless.com/products/rak831-gateway-module)
  * [RAK 833 Concentrator](https://store.rakwireless.com/products/rak833-gateway-module)
  * [RAK 2245 Pi Hat](https://store.rakwireless.com/products/rak2245-pi-hat)
  * [RAK 2247 Concentrator](https://store.rakwireless.com/products/rak2247-lpwan-gateway-concentrator-module)
* SX1302
  * [RAK 2287 Concentrator](https://store.rakwireless.com/products/rak2287-lpwan-gateway-concentrator-module)
  * [Seeed WM1302](https://www.seeedstudio.com/WM1302-LoRaWAN-Gateway-Module-SPI-EU868-p-4889.html)

* SX1303
  * [RAK 5146 Concentrator](https://store.rakwireless.com/collections/wislink-lpwan/products/wislink-lpwan-concentrator-rak5146)

Other SPI concentrators might also work.


### Software

If you are going to use docker to deploy the project, you will need:

* An OS image for your board (Raspberry Pi OS, Ubuntu OS for ARM,...)
* Docker (and optionally docker-compose) on the machine (see below for instal·lation instructions)

If you are going to use this image with Balena, you will need:

* A balenaCloud account ([sign up here](https://dashboard.balena-cloud.com/))

On both cases you will also need:

* A The Things Stack V3 account [here](https://ttc.eu1.cloud.thethings.industries/console/)
* [balenaEtcher](https://balena.io/etcher) to burn the image on the SD or the BalenaFin


Once all of this is ready, you are able to deploy this repository following instructions below.


## Installing docker & docker-compose on the OS

If you are going to run this project directly using docker (not using Balena) then you will need to install docker on the OS first. This is pretty staring forward, just follow these instructions:

```
sudo apt-get update && sudo apt-get upgrade -y
curl -sSL https://get.docker.com | sh
sudo usermod -aG docker ${USER}
newgrp docker
sudo apt install -y python3 python3-dev python3-pip libffi-dev libssl-dev
sudo pip3 install docker-compose
sudo systemctl enable docker
```

Once done, you should be able to check the instalation is alright by testing:

```
docker --version
docker-compose --version
```


## Deploy the code

### Via docker-compose

You can use the `docker-compose.yml` file below to configure and run your instance of Basics™ Station. 

```
version: '3.7'

services:

  basicstation:
    image: xoseperez/basicstation:latest
    container_name: basicstation
    restart: unless-stopped
    privileged: true
    network_mode: host      # required to read main interface MAC instead of virtual one
    environment:
      MODEL: "SX1301"
      GW_GPS: "false"
      GW_RESET_GPIO: 17
      TTN_REGION: "eu1"     # currently available: eu1, nam1, au1
      TC_KEY: "..."         # Copy here your API key from the LNS
      #TC_URI:              # uses TTN server by default, based on the TTN_REGION variable
      #TC_TRUST:            # uses TTN certificates by default
```

Modify the environment variables to match your setup. You will need a gateway key (`TC_KEY` variable above) to connect it to your LoRaWAN Network Server (LNS). If you want to do it beforehand you will need the Gateway EUI. Check the `Get the EUI of the LoRa Gateway` section below to know how. Otherwise, check the logs messages when the service starts to know the Gateway EUI to use.

### Build the image (not required)

In case you can not pull the already built image from Docker Hub or if you want to customize the cose, you can easily build the image by using the [buildx extension](https://docs.docker.com/buildx/working-with-buildx/) of docker and push it to your local repository by doing:

```
docker buildx bake --load
```

Once built (it will take some minutes) you can bring it up by using "basictation" as the image name in your `docker-compose.yml` file.

### Via [Balena Deploy](https://www.balena.io/docs/learn/deploy/deploy-with-balena-button/)

Running this project is as simple as deploying it to a balenaCloud application. You can do it in just one click by using the button below:

[![](https://www.balena.io/deploy.png)](https://dashboard.balena-cloud.com/deploy?repoUrl=https://github.com/balenalabs/basicstation)

Follow instructions, click Add a Device and flash an SD card with that OS image dowloaded from balenaCloud. Enjoy the magic 🌟Over-The-Air🌟!


### Via [Balena-CLI](https://www.balena.io/docs/reference/balena-cli/)

If you are a balena CLI expert, feel free to use balena CLI.

- Sign up on [balena.io](https://dashboard.balena.io/signup)
- Create a new application on balenaCloud.
- Clone this repository to your local workspace.
- Using [Balena CLI](https://www.balena.io/docs/reference/cli/), push the code with `balena push <application-name>`
- See the magic happening, your device is getting updated 🌟Over-The-Air🌟!


## Configure the Gateway


### Define your MODEL

The model is defined depending on the version of the LoRa concentrator: `SX1301`, `SX1302` or `SX1303`. 

Check the table at the top of this page to know what concentrator chip to use depending on your module. If the module is not on the list check the manufacturer to see which one to use. It's important to change the `MODEL` variable (in you `docker-compose.yml` file or in balenaCloud) to the correct one. The default model is the `SX1301`.


### Get the EUI of the LoRa Gateway

The LoRa gateways are manufactured with a unique 64 bits (8 bytes) identifier, called EUI, which can be used to register the gateway on the LoRaWAN Network Server. To get the EUI from your board it’s important to know the Ethernet MAC address of it (this is not going to work if your device does not have Ethernet port). The ```EUI``` will be the Ethernet mac address (6 bytes), which is unique, expanded with 2 more bytes (FFFE). This is a standard way to increment the MAC address from 6 to 8 bytes.

If using docker directly you can get the EUI for the gateway by running:

```
docker run -it --network host --rm xoseperez/basicstation:latest ./get_eui.sh

```

You can do so before bringing up the service, so you first get the EUI, registert the gateway and get the KEY to populate it on the `docker-compose.yml` file.

If using balenaCloud the ```EUI``` will be visible as a TAG on the device dashboard. Be careful when you copy the tag, as other characters will be copied.


### Using TTN? Define your REGION

If you plan to use The Things Network, set the `TTN_REGION` variable. It needs to be changed if your region is not Europe. The default value is `eu1` for the European server. By setting this variable (`TTN_REGION`) the `TC_URI` will be generated automatically. 


### Not using TTN?

In case that you want to point to another LNS different from The Things Network you will have to define a specific `TC_URI`. You will also have to define the `TC_TRUST` variable with the public certificate for your LSN server. Check your provider for the right value for this variable. It should be something like (in one line): 

```
-----BEGIN CERTIFICATE----- MIIDSjCCAjKgAwIBAgIQRK+wgNajJ7qJMDmGLvhAazANBgkqhkiG9w0BAQUFADA/MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMTDkRTVCBSb290IENBIFgzMB4XDTAwMDkzMDIxMTIxOVoXDTIxMDkzMDE0MDExNVowPzEkMCIGA1UEChMbRGlnaXRhbCBTaWduYXR1cmUgVHJ1c3QgQ28uMRcwFQYDVQQDEw5EU1QgUm9vdCBDQSBYMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAN+v6ZdQCINXtMxiZfaQguzH0yxrMMpb7NnDfcdAwRgUi+DoM3ZJKuM/IUmTrE4Orz5Iy2Xu/NMhD2XSKtkyj4zl93ewEnu1lcCJo6m67XMuegwGMoOifooUMM0RoOEqOLl5CjH9UL2AZd+3UWODyOKIYepLYYHsUmu5ouJLGiifSKOeDNoJjj4XLh7dIN9bxiqKqy69cK3FCxolkHRyxXtqqzTWMIn/5WgTe1QLyNau7Fqckh49ZLOMxt+/yUFw7BZy1SbsOFU5Q9D8/RhcQPGX69Wam40dutolucbY38EVAjqr2m7xPi71XAicPNaDaeQQmxkqtilX4+U9m5/wAl0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFMSnsaR7LHH62+FLkHX/xBVghYkQMA0GCSqGSIb3DQEBBQUAA4IBAQCjGiybFwBcqR7uKGY3Or+Dxz9LwwmglSBd49lZRNI+DT69ikugdB/OEIKcdBodfpga3csTS7MgROSR6cz8faXbauX+5v3gTt23ADq1cEmv8uXrAvHRAosZy5Q6XkjEGB5YGV8eAlrwDPGxrancWYaLbumR9YbK+rlmM6pZW87ipxZzR8srzJmwN0jP41ZL9c8PDHIyh8bwRLtTcm1D9SZImlJnt1ir/md2cXjbDaJWFBM5JDGFoqgCWjBH4d1QB7wCCZAA62RjYJsWvIjJEubSfZGL+T0yjWW06XyxV3bqxbYoOb8VZRzI9neWagqNdwvYkQsEjgfbKbYK7p2CNTUQ -----END CERTIFICATE-----
```


### Configure your The Things Stack gateway

1. Sign up at [The Things Stack console](https://ttc.eu1.cloud.thethings.industries/console/).
2. Click "Go to Gateways" icon.
3. Click the "Add gateway" button.
4. Introduce the data for the gateway.
5. Paste the EUI from the balenaCloud tags.
6. Complete the form and click Register gateway.
7. Once the gateway is created, click "API keys" link.
8. Click "Add API key" button.
9. Select "Grant individual rights" and then "Link as Gateway to a Gateway Server for traffic exchange ..." and then click "Create API key".
10. Copy the API key generated and paste it into your docker-compose.yml file or use it on balenaCloud as ```TC_KEY``` variable.


### Basics Station Service Variables

These variables you can set them under the `environment` tag in the `docker-compose.yml` file or using an environment file (with the `env_file` tag). If you are using Balena you can also set them in the `Device Variables` tab for the device (or globally for the whole application).

Variable Name | Value | Description | Default
------------ | ------------- | ------------- | -------------
**`MODEL`** | `STRING` | ```SX1301```, ```SX1302``` or ```SX1303``` | ```SX1301```
**`GW_GPS`** | `STRING` | Enables GPS | true or false
**`GW_RESET_GPIO`** | `INT` | GPIO number that resets (Broadcom pin number, if not defined, it's calculated based on the GW_RESET_PIN) | 17
**`GW_POWER_EN_GPIO`** | `INT` | GPIO number that enables power (by pulling HIGH) to the concentrator (Broadcom pin number). 0 means no required. | 0
**`TTN_REGION`** | `STRING` | Region of the TTN server to use | ```eu1```
**`TC_TRUST`** | `STRING` | Certificate for the server | Automatically retrieved from LetsEncryt for TTN
**`TC_URI`** | `STRING` | Basics Station TC URI to get connected. | Automatically created based on TTN_REGION for TTN
**`TC_KEY`** | `STRING` | Unique TTN Gateway Key used for TTS Community Edition | Paste API key from TTN console

When using The Things Stack Community Edition the `TC_URI` and `TC_TRUST` values are automatically populated to use ```wss://eu1.cloud.thethings.network:8887```. If your region is not EU you can set it using ```TTN_REGION```. At the moment there is only one server avalable is ```eu1```.


## Troubleshoothing

It's possible that on the TTN Console the gateway appears as Not connected if it's not receiving any LoRa message. Sometimes the websockets connection among the LoRa Gateway and the server can get broken. However a new LoRa package will re-open the websocket between the Gateway and TTN or TTI.

Feel free to introduce issues on this repo and contribute with solutions.


## Attribution

- This is an adaptation of the [Semtech Basics Station repository](https://github.com/lorabasics/basicstation). Documentation [here](https://doc.sm.tc/station).
- This is in part working thanks of the work of Jose Marcelino from RAK Wireless, Xose Pérez from Allwize & RAK Wireless and Marc Pous from balena.io.
- This is in part based on excellent work done by Rahul Thakoor from the Balena.io Hardware Hackers team.
