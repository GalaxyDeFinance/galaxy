// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

/**
 * @title IPool
 *
 * @notice Defines the basic interface for an Galaxy Pool.
 **/
interface IGalaxy {

    struct BorrowInfo {
        string orderId;
        uint256 borrowAmount;
        address tokenAddress; // this address will be 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE when borrow ETH
    }

}
