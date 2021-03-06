import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:rxdart/rxdart.dart';

import 'LighthousePowerState.dart';

///The bluetooth service that handles the power state of the device.
final Guid _PWR_SERVICE = Guid('00001523-1212-efde-1523-785feabcd124');

///The characteristic that handles the power state of the device.
final Guid _PWR_CHARACTERISTIC = Guid('00001525-1212-efde-1523-785feabcd124');

/// A single lighthouse device. (This doesn't mean that it is a valid device.
/// if used outside of the [LighthouseProvider] then you can be (almost) certain
/// that it is a valid device).
///
/// Top get a device use the [LighthouseProvider]'s
/// [LighthouseProvider.lighthouseDevices] stream to get a list of currently
/// visible devices.
class LighthouseDevice {
  LighthouseDevice(BluetoothDevice device) : _device = device;

  ///Get the name of the device.
  String get name => _device.name;

  ///Get the id (MAC) of the device.
  DeviceIdentifier get id => _device.id;

  ///Get the power state of the device as an int.
  Stream<int> get powerState {
    this._startPowerStateStream();
    return this._powerState.stream;
  }

  ///Get the power state of the device as a [LighthousePowerState] "enum".
  Stream<LighthousePowerState> get powerStateEnum => this.powerState.map((e) {
        return LighthousePowerState.fromByte(e);
      });

  final BluetoothDevice _device;
  BluetoothCharacteristic _characteristic;
  BehaviorSubject<int> _powerState = BehaviorSubject.seeded(0xFF);
  StreamSubscription _powerStateSubscription;

  ///Check if the device is a valid Lighthouse device.
  ///
  /// This method is already done by [LighthouseProvider] and thus doesn't
  /// have to be done again.
  ///
  /// **Note:** This will also connect to the device.
  Future<bool> isValid() async {
    debugPrint('Connecting to device: ${this._device.id.toString()}');
    await this._device.connect(timeout: Duration(seconds: 10)).catchError((e) {
      debugPrint(
          'Connection timedout for device: ${this._device.id.toString()}');
      return false;
    }, test: (e) => e is TimeoutException);

    debugPrint('Finding service for device: ${this._device.id.toString()}');
    List<BluetoothService> services = await this._device.discoverServices();
    for (final service in services) {
      if (service.uuid != _PWR_SERVICE) {
        continue;
      }
      // Find the correct characteristic.
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == _PWR_CHARACTERISTIC) {
          this._characteristic = characteristic;
          return true;
        }
      }
    }
    return false;
  }

  ///Disconnect from the device.
  Future disconnect() async {
    debugPrint('Disconnecting from the powerstate');
    await this._powerStateSubscription.cancel();
    this._characteristic = null;
    await this._device.disconnect();
  }

  ///Change the state of the device.
  ///
  /// The only valid options are:
  ///  - [LighthousePowerState.ON]
  ///  - [LighthousePowerState.STANDBY]
  ///
  /// When an invalid [newState] is given then this will only be logged in the
  /// console and `return` immediately.
  /// If for what ever reason the [isValid] function didn't complete correctly
  /// and then this method is called, then it will also just `return`.
  Future changeState(LighthousePowerState newState) async {
    if (newState == LighthousePowerState.UNKNOWN) {
      debugPrint('Cannot set powerstate to unknown');
      return;
    }
    if (newState == LighthousePowerState.BOOTING) {
      debugPrint('Cannot change powerstate to booting');
      return;
    }
    if (this._characteristic == null) {
      return;
    }
    await this._characteristic.write([newState.setByte], withoutResponse: true);
  }

  bool _powerStateTransaction = false;

  ///Start the power state stream.
  ///
  /// If this method is called while there is already an active stream then it
  /// will do nothing.
  void _startPowerStateStream() {
    if (this._powerStateSubscription != null) {
      if (this._powerStateSubscription.isPaused) {
        this._powerStateSubscription.resume();
        return;
      }
      return;
    }
    _powerStateTransaction = false;
    _powerStateSubscription =
        Stream.periodic(Duration(milliseconds: 1000)).listen((_) {
      if (this._characteristic != null) {
        if (!_powerStateTransaction) {
          _powerStateTransaction = true;
          this._characteristic.read().then((data) {
            if (data.length >= 1) {
              this._powerState.add(data[0]);
            }
            _powerStateTransaction = false;
          }).catchError((error) {
            debugPrint(error);
          });
        }
      } else {
        debugPrint('Cleaning-up old subscription!');
        final subscription = this._powerStateSubscription;
        if (subscription != null) {
          subscription.cancel();
        }
      }
    });
    _powerStateSubscription.onDone(() {
      debugPrint('Cleaning-up powerstate subscription!');
      _powerStateSubscription = null;
    });
  }
}

/// This is a fake [LighthouseDevice] that won't actually do anything.
///
/// This always uses fake data and doesn't actually connect to a device. And
/// always uses fake data.
class LighthouseDeviceFake extends LighthouseDevice {
  LighthouseDeviceFake() : super(null) {
    final random = new Random();
    for (var i = 0; i < 8; i++) {
      this._name += random.nextInt(16).toRadixString(16).toUpperCase();
    }
    String id = '00:00:00:00:00:';
    id += random.nextInt(16).toRadixString(16).toUpperCase();
    id += random.nextInt(16).toRadixString(16).toUpperCase();
    this._id = new DeviceIdentifier(id);

    if (random.nextBool()) {
      this._powerState.add(LighthousePowerState.ON.stateByte);
    } else {
      this._powerState.add(LighthousePowerState.STANDBY.stateByte);
    }
  }

  String _name = 'LHB-';

  @override
  String get name => _name;

  DeviceIdentifier _id;

  @override
  DeviceIdentifier get id => _id;

  BehaviorSubject<int> _powerState = BehaviorSubject.seeded(0xFF);

  @override
  Stream<int> get powerState => _powerState.stream;

  @override
  Stream<LighthousePowerState> get powerStateEnum =>
      this.powerState.map((e) => LighthousePowerState.fromByte(e));

  @override
  Future<bool> isValid() async {
    return true;
  }

  @override
  Future disconnect() async {
    return;
  }

  @override
  Future changeState(LighthousePowerState newState) async {
    switch (newState) {
      case LighthousePowerState.BOOTING:
      case LighthousePowerState.UNKNOWN:
        return;
      case LighthousePowerState.ON:
        this._powerState.add(LighthousePowerState.ON.setByte);
        await Future.delayed(new Duration(milliseconds: 10));
        this._powerState.add(LighthousePowerState.BOOTING.stateByte);
        await Future.delayed(new Duration(milliseconds: 1200));
        this._powerState.add(LighthousePowerState.ON.stateByte);
        break;
      case LighthousePowerState.STANDBY:
        this._powerState.add(LighthousePowerState.STANDBY.setByte);
    }
  }
}
