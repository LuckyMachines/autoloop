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

### deregisterAutoLoop

```solidity
function deregisterAutoLoop() external returns (bool success)
```

AutoLoop compatible contract deregisters itself

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

### deregisterAutoLoopFor

```solidity
function deregisterAutoLoopFor(address autoLoopCompatibleContract) external returns (bool success)
```

deregister an AutoLoop compatible contract (must have DEFAULT_ADMIN_ROLE on contract being deregistered)

#### Parameters

| Name                       | Type    | Description                               |
| -------------------------- | ------- | ----------------------------------------- |
| autoLoopCompatibleContract | address | the address of the contract to deregister |

#### Return Values

| Name    | Type | Description                                    |
| ------- | ---- | ---------------------------------------------- |
| success | bool | - whether or not the contract was deregistered |

### registerController

```solidity
function registerController() external returns (bool success)
```

register an AutoLoop controller

#### Return Values

| Name    | Type | Description                                    |
| ------- | ---- | ---------------------------------------------- |
| success | bool | - whether or not the controller was registered |

### deregisterController

```solidity
function deregisterController() external
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

### \_deregisterAutoLoop

```solidity
function _deregisterAutoLoop(address registrant) internal
```

_deregisters AutoLoop compatible contract if possible. No pre-checks are required although they can save gas on a redundant call to deregister._

### \_registerController

```solidity
function _registerController(address registrant) internal
```

_registers controller. This should not be called unless a pre-check has been made to verify the controller can be registered._

### \_deregisterController

```solidity
function _deregisterController(address registrant) internal
```

_deregisters controller if possible. No pre-checks are required although they can save gas on a redundant call to deregister._

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

### AutoLoopDeregistered

```solidity
event AutoLoopDeregistered(address autoLoopAddress, address registrarAddress, uint256 timeStamp)
```

### ControllerRegistered

```solidity
event ControllerRegistered(address controllerAddress, address registrarAddress, uint256 timeStamp)
```

### ControllerDeregistered

```solidity
event ControllerDeregistered(address controllerAddress, address registrarAddress, uint256 timeStamp)
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

### deregisterAutoLoop

```solidity
function deregisterAutoLoop(address registrantAddress) external
```

### registerController

```solidity
function registerController(address registrantAddress) external
```

### deregisterController

```solidity
function deregisterController(address registrantAddress) external
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

### deregisterAutoLoop

```solidity
function deregisterAutoLoop(address registrarAddress) public
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

---

## VRFVerifier

Gas-efficient ECVRF proof verification library for secp256k1 using the `ecrecover` precompile.

Implements ECVRF-SECP256K1-SHA256-TAI (cipher suite `0xFE`). Instead of full EC point multiplication on-chain (~millions of gas), uses `ecrecover` as an EC multiplication oracle (~3k gas).

### fastVerify

```solidity
function fastVerify(
    uint256[2] memory publicKey,
    uint256[4] memory proof,
    bytes memory message,
    uint256[2] memory uPoint,
    uint256[4] memory vComponents
) internal pure returns (bool)
```

Verifies an ECVRF proof using precomputed helper points.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| publicKey | uint256[2] | [x, y] coordinates of the prover's public key |
| proof | uint256[4] | [gamma_x, gamma_y, c, s] VRF proof components |
| message | bytes | The input message (seed) that was signed |
| uPoint | uint256[2] | Precomputed point U = s*G - c*PublicKey |
| vComponents | uint256[4] | [sH_x, sH_y, cGamma_x, cGamma_y] precomputed components |

### gammaToHash

```solidity
function gammaToHash(uint256 gammaX, uint256 gammaY) internal pure returns (bytes32)
```

Derives a deterministic random output from a verified VRF proof: `keccak256("VRF_OUTPUT", gammaX, gammaY)`.

### hashToCurve

```solidity
function hashToCurve(
    uint256[2] memory publicKey,
    bytes memory message
) internal pure returns (uint256 x, uint256 y)
```

Hash-to-curve using try-and-increment (TAI). Deterministically maps a message to a secp256k1 point.

### ecAdd

```solidity
function ecAdd(
    uint256 x1, uint256 y1,
    uint256 x2, uint256 y2
) internal pure returns (uint256 x3, uint256 y3)
```

EC point addition using standard chord-and-tangent formulas.

### ecSub

```solidity
function ecSub(
    uint256 x1, uint256 y1,
    uint256 x2, uint256 y2
) internal pure returns (uint256, uint256)
```

EC point subtraction: `(x1,y1) + (x2, -y2)`.

---

## AutoLoopVRFCompatible

Abstract base for AutoLoop-compatible contracts that require verifiable randomness. Extends `AutoLoopCompatible` and uses `VRFVerifier` for on-chain proof verification.

Controllers generate ECVRF proofs off-chain and wrap them around the original `progressWithData`. This contract verifies the proof and exposes the VRF output as a `bytes32` random value.

### VRF Envelope Encoding

```
abi.encode(
    uint8 vrfVersion,       // 1 = ECVRF-SECP256K1-SHA256-TAI
    uint256[4] proof,       // [gamma_x, gamma_y, c, s]
    uint256[2] uPoint,      // precomputed for fastVerify
    uint256[4] vComponents, // precomputed for fastVerify
    bytes gameData          // original progressWithData from shouldProgressLoop
)
```

### VRF\_VERSION

```solidity
uint8 public constant VRF_VERSION = 1
```

VRF version constant (ECVRF-SECP256K1-SHA256-TAI).

### VRF\_INTERFACE\_ID

```solidity
bytes4 public constant VRF_INTERFACE_ID = bytes4(keccak256("AutoLoopVRFCompatible"))
```

ERC-165 interface ID for VRF-compatible contracts.

### controllerPublicKeys

```solidity
mapping(address => uint256[2]) public controllerPublicKeys
```

Controller address to [x, y] public key coordinates.

### controllerKeyRegistered

```solidity
mapping(address => bool) public controllerKeyRegistered
```

Tracks which controllers have registered public keys.

### registerControllerKey

```solidity
function registerControllerKey(
    address controller,
    uint256 pkX,
    uint256 pkY
) external
```

Register a controller's secp256k1 public key for VRF proof verification. Only the controller itself or an admin can call this. The key must be a valid point on secp256k1.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| controller | address | The controller address |
| pkX | uint256 | x-coordinate of the public key |
| pkY | uint256 | y-coordinate of the public key |

### computeSeed

```solidity
function computeSeed(uint256 loopID) public view returns (bytes memory)
```

Compute the deterministic seed for a given loop ID: `keccak256(address(this), loopID)`. Controllers cannot choose seeds.

### \_verifyAndExtractRandomness

```solidity
function _verifyAndExtractRandomness(
    bytes calldata progressWithData,
    address controller
) internal returns (bytes32 randomness, bytes memory gameData)
```

Verify VRF proof and extract randomness from the VRF envelope. Called by the implementing contract's `progressLoop()`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| progressWithData | bytes | The VRF-wrapped data from the controller |
| controller | address | The controller address (tx.origin or passed from AutoLoop) |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| randomness | bytes32 | The verified random value |
| gameData | bytes | The original game-specific data from the envelope |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool)
```

ERC-165 support — returns `true` for `VRF_INTERFACE_ID` and all parent interfaces.

### ControllerKeyRegistered

```solidity
event ControllerKeyRegistered(address indexed controller, uint256 pkX, uint256 pkY)
```

Emitted when a controller registers their VRF public key.

### VRFRandomnessVerified

```solidity
event VRFRandomnessVerified(uint256 indexed loopID, bytes32 randomness, address indexed controller)
```

Emitted when VRF randomness is verified and consumed.

---

## RandomGame

Sample dice-roll game demonstrating AutoLoop VRF integration. On each tick, the controller provides an ECVRF proof. The contract verifies it and uses the VRF output to produce a fair 1-6 dice roll.

### lastRoll

```solidity
uint256 public lastRoll
```

The last dice roll result (1-6).

### totalRolls

```solidity
uint256 public totalRolls
```

Total number of rolls performed.

### interval

```solidity
uint256 public interval
```

Minimum time between rolls (seconds).

### rollHistory

```solidity
uint256[10] public rollHistory
```

Ring buffer of the last 10 rolls.

### constructor

```solidity
constructor(uint256 updateInterval) public
```

### shouldProgressLoop

```solidity
function shouldProgressLoop() external view returns (bool loopIsReady, bytes memory progressWithData)
```

Returns `true` when `block.timestamp - lastTimeStamp > interval`. Passes `_loopID` as `progressWithData`.

### progressLoop

```solidity
function progressLoop(bytes calldata progressWithData) external
```

Verifies the VRF proof via `_verifyAndExtractRandomness()`, decodes the loop ID, re-checks timing, and performs a dice roll.

### getRecentRolls

```solidity
function getRecentRolls() external view returns (uint256[10] memory)
```

Returns all 10 entries in the roll history ring buffer.

### DiceRolled

```solidity
event DiceRolled(uint256 indexed loopID, uint256 roll, bytes32 randomness, uint256 timestamp)
```

Emitted on each dice roll with the loop ID, result (1-6), raw randomness, and block timestamp.
