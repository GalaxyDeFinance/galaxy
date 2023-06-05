// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.10;

import {IPriceOracle} from '../../interfaces/IPriceOracle.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {IACLManager} from '../../interfaces/IACLManager.sol';
import {Errors} from '../../protocol/libraries/helpers/Errors.sol';
contract PriceOracle is IPriceOracle {
  IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
  // Map of asset prices (asset => price)
  mapping(address => uint256) internal prices;

  uint256 internal ethPriceUsd;

  event AssetPriceUpdated(address asset, uint256 price, uint256 timestamp);
  event EthPriceUpdated(uint256 price, uint256 timestamp);

  /**
 * @dev Only asset listing or pool admin can call functions marked by this modifier.
   **/
  modifier onlyAssetListingOrPoolAdmins() {
    _onlyAssetListingOrPoolAdmins();
    _;
  }


  constructor(IPoolAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
  }

  function getAssetPrice(address asset) external view override returns (uint256) {
    return prices[asset];
  }

  function setAssetPrice(address asset, uint256 price) external override onlyAssetListingOrPoolAdmins {
    prices[asset] = price;
    emit AssetPriceUpdated(asset, price, block.timestamp);
  }

  function getEthUsdPrice() external view returns (uint256) {
    return ethPriceUsd;
  }

  function setEthUsdPrice(uint256 price) external onlyAssetListingOrPoolAdmins {
    ethPriceUsd = price;
    emit EthPriceUpdated(price, block.timestamp);
  }


  function _onlyAssetListingOrPoolAdmins() internal view {
    IACLManager aclManager = IACLManager(ADDRESSES_PROVIDER.getACLManager());
    require(
      aclManager.isAssetListingAdmin(msg.sender) || aclManager.isPoolAdmin(msg.sender),
      Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN
    );
  }
}
