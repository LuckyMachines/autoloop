// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface GameLoopCompatibleInterface {
    function shouldProgressLoop() external view returns (bool);

    // No guarantees on the data passed in. Should not be solely relied on.
    // Re-verify any data passed through progressWithData.
    function progressLoop() external;
}
