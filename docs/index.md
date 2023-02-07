# Solidity API

## AutoLoop

### constructor

```solidity
constructor() public
```

### MAX_GAS

```solidity
uint256 MAX_GAS
```

### GAS_BUFFER

```solidity
uint256 GAS_BUFFER
```

### GAS_THRESHOLD

```solidity
uint256 GAS_THRESHOLD
```

### balance

```solidity
mapping(address => uint256) balance
```

### maxGas

```solidity
mapping(address => uint256) maxGas
```

### progressLoop

```solidity
function progressLoop(address contractAddress, bytes progressWithData) external
```

progresses loop on AutoLoop compatible contract

#### Parameters

| Name             | Type    | Description                                  |
| ---------------- | ------- | -------------------------------------------- |
| contractAddress  | address | the address of the contract receiving update |
| progressWithData | bytes   | some data to pass along with update          |

### addController

```solidity
function addController(address controllerAddress) public
```

### removeController

```solidity
function removeController(address controllerAddress) public
```

### deposit

```solidity
function deposit(address registeredUser) external payable
```

### requestRefund

```solidity
function requestRefund(address registeredUser) external
```

### setMaxGas

```solidity
function setMaxGas(address registerdUser, uint256 maxGasAmount) external
```

### \_maxGas

```solidity
function _maxGas(address user) internal view returns (uint256 gasAmount)
```

## AutoLoopCompatible

## AutoLoopCompatibleInterface

### shouldProgressLoop

```solidity
function shouldProgressLoop() external view returns (bool loopIsReady, bytes progressWithData)
```

### progressLoop

```solidity
function progressLoop(bytes progressWithData) external
```

## AutoLoopRegistrar

### AUTO_LOOP

```solidity
contract AutoLoop AUTO_LOOP
```

### REGISTRY

```solidity
contract AutoLoopRegistry REGISTRY
```

### constructor

```solidity
constructor(address autoLoopAddress, address registryAddress, address adminAddress) public
```

### registerAutoLoop

```solidity
function registerAutoLoop() external returns (bool success)
```

AutoLoop compatible contract registers itself

#### Return Values

| Name    | Type | Description                                      |
| ------- | ---- | ------------------------------------------------ |
| success | bool | - whether the registration was successful or not |

### unregisterAutoLoop

```solidity
function unregisterAutoLoop() external returns (bool success)
```

AutoLoop compatible contract unregisters itself

#### Return Values

| Name    | Type | Description                                        |
| ------- | ---- | -------------------------------------------------- |
| success | bool | - whether the unregistration was successful or not |

### registerAutoLoopFor

```solidity
function registerAutoLoopFor(address autoLoopCompatibleContract) external returns (bool success)
```

register an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being registered)

#### Parameters

| Name                       | Type    | Description                             |
| -------------------------- | ------- | --------------------------------------- |
| autoLoopCompatibleContract | address | the address of the contract to register |

#### Return Values

| Name    | Type | Description                                  |
| ------- | ---- | -------------------------------------------- |
| success | bool | - whether or not the contract was registered |

### unregisterAutoLoopFor

```solidity
function unregisterAutoLoopFor(address autoLoopCompatibleContract) external returns (bool success)
```

unregister an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being unregistered)

#### Parameters

| Name                       | Type    | Description                               |
| -------------------------- | ------- | ----------------------------------------- |
| autoLoopCompatibleContract | address | the address of the contract to unregister |

#### Return Values

| Name    | Type | Description                                    |
| ------- | ---- | ---------------------------------------------- |
| success | bool | - whether or not the contract was unregistered |

### registerController

```solidity
function registerController() external returns (bool success)
```

register an AutoLoop controller

#### Return Values

| Name    | Type | Description                                    |
| ------- | ---- | ---------------------------------------------- |
| success | bool | - whether or not the controller was registered |

### unregisterController

```solidity
function unregisterController() external
```

uregister an AutoLoop controller

### canRegisterAutoLoop

```solidity
function canRegisterAutoLoop(address registrantAddress, address autoLoopCompatibleContract) public view returns (bool canRegister)
```

check if a contract can be registered

#### Parameters

| Name                       | Type    | Description                                                                               |
| -------------------------- | ------- | ----------------------------------------------------------------------------------------- |
| registrantAddress          | address | the address that will register the contract (address of the contract if self-registering) |
| autoLoopCompatibleContract | address | the AutoLoop compatible contract to be registered                                         |

#### Return Values

| Name        | Type | Description                                     |
| ----------- | ---- | ----------------------------------------------- |
| canRegister | bool | - whether or not the contract can be registered |

### canRegisterController

```solidity
function canRegisterController(address registrantAddress) public view returns (bool canRegister)
```

check if a controller can be registered

#### Parameters

| Name              | Type    | Description                                    |
| ----------------- | ------- | ---------------------------------------------- |
| registrantAddress | address | the address of the controller to be registered |

#### Return Values

| Name        | Type | Description                                       |
| ----------- | ---- | ------------------------------------------------- |
| canRegister | bool | - whether or not the controller can be registered |

### \_registerAutoLoop

```solidity
function _registerAutoLoop(address registrant) internal
```

_registers AutoLoop compatible contract. This should not be called unless a pre-check has been made to verify the contract can be registered._

### \_unregisterAutoLoop

```solidity
function _unregisterAutoLoop(address registrant) internal
```

_unregisters AutoLoop compatible contract if possible. No pre-checks are required although they can save gas on a redundant call to unregister._

### \_registerController

```solidity
function _registerController(address registrant) internal
```

_registers controller. This should not be called unless a pre-check has been made to verify the controller can be registered._

### \_unregisterController

```solidity
function _unregisterController(address registrant) internal
```

_unregisters controller if possible. No pre-checks are required although they can save gas on a redundant call to unregister._

## AutoLoopRegistry

### isRegisteredAutoLoop

```solidity
mapping(address => bool) isRegisteredAutoLoop
```

### isRegisteredController

```solidity
mapping(address => bool) isRegisteredController
```

### \_registeredAutoLoopIndex

```solidity
mapping(address => uint256) _registeredAutoLoopIndex
```

### \_registeredControllerIndex

```solidity
mapping(address => uint256) _registeredControllerIndex
```

### \_registeredAutoLoops

```solidity
address[] _registeredAutoLoops
```

### \_registeredControllers

```solidity
address[] _registeredControllers
```

### AutoLoopRegistered

```solidity
event AutoLoopRegistered(address autoLoopAddress, address registrarAddress, uint256 timeStamp)
```

### AutoLoopUnregistered

```solidity
event AutoLoopUnregistered(address autoLoopAddress, address registrarAddress, uint256 timeStamp)
```

### ControllerRegistered

```solidity
event ControllerRegistered(address controllerAddress, address registrarAddress, uint256 timeStamp)
```

### ControllerUnregistered

```solidity
event ControllerUnregistered(address controllerAddress, address registrarAddress, uint256 timeStamp)
```

### constructor

```solidity
constructor(address adminAddress) public
```

### getRegisteredAutoLoops

```solidity
function getRegisteredAutoLoops() public view returns (address[] autoLoops)
```

### getRegisteredControllers

```solidity
function getRegisteredControllers() public view returns (address[] controllers)
```

### cleanControllerList

```solidity
function cleanControllerList() public
```

### cleanAutoLoopList

```solidity
function cleanAutoLoopList() public
```

### registerAutoLoop

```solidity
function registerAutoLoop(address registrantAddress) external
```

### unregisterAutoLoop

```solidity
function unregisterAutoLoop(address registrantAddress) external
```

### registerController

```solidity
function registerController(address registrantAddress) external
```

### unregisterController

```solidity
function unregisterController(address registrantAddress) external
```

## AutoLoopRoles

### CONTROLLER_ROLE

```solidity
bytes32 CONTROLLER_ROLE
```

### REGISTRY_ROLE

```solidity
bytes32 REGISTRY_ROLE
```

### REGISTRAR_ROLE

```solidity
bytes32 REGISTRAR_ROLE
```

### setRegistrar

```solidity
function setRegistrar(address registrarAddress) external
```

### removeRegistrar

```solidity
function removeRegistrar(address registrarAddress) external
```

## NumberGoUp

### number

```solidity
uint256 number
```

### interval

```solidity
uint256 interval
```

### lastTimeStamp

```solidity
uint256 lastTimeStamp
```

### \_loopID

```solidity
uint256 _loopID
```

### constructor

```solidity
constructor(uint256 updateInterval) public
```

### registerAutoLoop

```solidity
function registerAutoLoop(address registrarAddress) public
```

### unregisterAutoLoop

```solidity
function unregisterAutoLoop(address registrarAddress) public
```

### shouldProgressLoop

```solidity
function shouldProgressLoop() external view returns (bool loopIsReady, bytes progressWithData)
```

### progressLoop

```solidity
function progressLoop(bytes progressWithData) external
```

### updateGame

```solidity
function updateGame() internal
```
