# WattiWatchman

The Watti Watchman is used to achieve precise zero-feed-in regulation in a highly time-sensitive
manner. The current setup is configured as follows: a smart meter is installed at the grid entry
point, with a pure battery system (powered by Victron), and a custom smart meter positioned
before the battery system. Multiple PV AC inverters operate passively within the system. Any
inverter can be integrated with the setup, provided it can request power from the battery to feed in
or charge, without relying on specific Victron features. For smart metering, Janitza devices are
utilized as they deliver consumption data via Modbus every 200ms. One device features integrated
Ethernet Modbus, while another connects via an RS485 Ethernet bridge to a Raspberry Pi. The Watti
Watchman adjusts to the desired power setpoint within milliseconds, constrained only by grid
protection measures. The entire system is designed for maximum observability, with Prometheus
configured to scrape data at 200ms intervals, ensuring precise and detailed monitoring.

The reason for not using the built-in Victron features lies in the complexity of configuration and
monitoring within the Victron system. Diagnosing issues or unexpected behavior becomes
challenging, particularly in cases of Cerbo overload. Instead, the focus was on implementing a
system that is thoroughly tested and highly flexible. The primary objective was to ensure maximum
monitoring capability, enabling detailed and reliable observation of all system parameters without
compromise.

### Victron Requirements

* The following must be installed: https://github.com/freakent/dbus-mqtt-devices.
  A grid meter will be created using `dbus-mqtt-devices`, and parameters will be updated via
  native FlashMQ mechanisms to minimize CPU usage.

* The Hub4ESS mode must be manually set to 3, as it cannot currently be determined
  automatically.

### Configuration

Configuration requires the creation of a `watti_watchman.yml` file, which is validated using a JSON 
schema. The compiled schema can be found at `dist/schema.json`, while individual YAML 
configuration files are located in the `schemas` folder (development only).
Details regarding the modules are covered in a later section. 

```yaml
mqtt_connections:
  - name: "mqtt_k8s"
    host: "mqtt-local.apps.svc.cluster.local"
    port: 1883

  - name: "mqtt_venus"
    host: "10.100.6.134"
    port: 1883

meters:
  - type: "Janitza"
    name: "hak"
    host: "10.100.6.27"
    port: 502
    unit: 2

  - type: "Janitza"
    name: "battery_janitza"
    host: "10.100.6.25"
    port: 502
    unit: 1

  - type: "Victron"
    name: "battery_victron"
    mqtt_connection_name: "mqtt_venus"
    id: abcdef012345

services:
  - type: "HassFeeder"
    mqtt_connection_name: "mqtt_k8s"
    update_interval: 5

  - type: "VictronGridFeeder"
    mqtt_connection_name: "mqtt_venus"
    grid_meter_name: "hak"

  - type: "ChargeController"
    grid_meter_name: "hak"
    battery_meter_name: "battery_janitza"
    battery_controller_name: "battery_victron"
    target_setpoint: 0
    charge_limits:
      "0": 9000
      "90": 2000
      "97": 1000
      "99": 500
    discharge_limits:
      "100": 6000
      "10": 1000
      "5": 0
```

#### Service: HassFeeder

The **HassFeeder** module enables integration with Home Assistant using MQTT for real-time data updates. 
This module periodically publishes power and energy metrics to the specified MQTT connection, making it 
suitable for Home Assistant setups requiring high-frequency energy monitoring.

#### Service: VictronGridFeeder

The **VictronGridFeeder** module, in combination with the **VictronGridProvider** service, integrates a 
virtual grid meter into the Victron Venus OS ecosystem. This allows users to maintain and utilize the 
native Victron user interface for monitoring and managing energy flows.

**How it works**: The module simulates a grid meter
by feeding data into Venus OS, making the grid meter accessible and 
readable within the system. This approach ensures seamless integration and usability of Victron's 
existing monitoring tools without requiring additional hardware.

#### Service: ChargeController

The **ChargeController** service dynamically manages battery charging and discharging to achieve 
a specified grid power setpoint. It uses real-time data from the grid meter, battery meter, and 
battery controller to calculate and adjust energy flow in milliseconds.

**Key Features:**

- Maintains a target grid power setpoint by regulating battery usage. 
- Implements configurable charge and discharge limits based on the battery's state of charge (SOC). 
- Operates with millisecond precision to ensure system stability and responsiveness. 
- Compatible with meters implementing the required interfaces.
