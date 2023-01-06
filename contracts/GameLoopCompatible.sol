// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/AutomationBase.sol";
import "./GameLoopCompatibleInterface.sol";

abstract contract AutomationCompatible is
    AutomationBase,
    GameLoopCompatibleInterface
{}
