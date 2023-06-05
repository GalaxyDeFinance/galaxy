// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.10;

interface IInvestmentEarnings {

    event NotedCancelReinvest(string orderId,string  status);
    event NotedWithdraw(uint64[] recordIds);
    event Processed(string orderId,uint256 status);

    function noteCancelReinvest(string calldata orderId,string calldata status) external;

    function noteWithdrawal(uint64[] calldata recordIds) external;

    function processBorrowing(string calldata orderId,uint256 status) external;
}