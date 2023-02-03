// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AutoLoopCompatibleInterface.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

abstract contract AutoLoopCompatible is
    AutoLoopCompatibleInterface,
    AccessControlEnumerable
{}
