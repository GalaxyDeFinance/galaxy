// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.10;

import {AggregatorInterface} from '../dependencies/chainlink/AggregatorInterface.sol';
import {Errors} from '../protocol/libraries/helpers/Errors.sol';
import {IACLManager} from '../interfaces/IACLManager.sol';
import {IPoolAddressesProvider} from '../interfaces/IPoolAddressesProvider.sol';
import {IPriceOracleGetter} from '../interfaces/IPriceOracleGetter.sol';
import {IGalaxyOracle} from '../interfaces/IGalaxyOracle.sol';

/**
 * @title GalaxyOracle
 *
 * @notice Contract to get asset prices, manage price sources and update the fallback oracle
 * - Use of Chainlink Aggregators as first source of price
 * - If the returned price by a Chainlink aggregator is <= 0, the call is forwarded to a fallback oracle
 * - Owned by the Galaxy governance
 */
contract GalaxyOracle is IGalaxyOracle {
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;

    // Map of asset price sources (asset => priceSource)
    mapping(address => AggregatorInterface) private assetsSources;
    address[] public priceFeedKeys;
    mapping(address => bool) public priceFeedMap;
    IPriceOracleGetter private _fallbackOracle;
    address public immutable override BASE_CURRENCY;
    uint256 public immutable override BASE_CURRENCY_UNIT;

    /**
     * @dev Only asset listing or pool admin can call functions marked by this modifier.
   **/
    modifier onlyAssetListingOrPoolAdmins() {
        _onlyAssetListingOrPoolAdmins();
        _;
    }

    /**
     * @notice Constructor
   * @param provider The address of the new PoolAddressesProvider
   * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   * @param fallbackOracle The address of the fallback oracle to use if the data of an
   *        aggregator is not consistent
   * @param baseCurrency The base currency used for the price quotes. If USD is used, base currency is 0x0
   * @param baseCurrencyUnit The unit of the base currency
   */
    constructor(
        IPoolAddressesProvider provider,
        address[] memory assets,
        address[] memory sources,
        address fallbackOracle,
        address baseCurrency,
        uint256 baseCurrencyUnit
    ) {
        ADDRESSES_PROVIDER = provider;
        _setFallbackOracle(fallbackOracle);
        _setAssetsSources(assets, sources);
        BASE_CURRENCY = baseCurrency;
        BASE_CURRENCY_UNIT = baseCurrencyUnit;
        emit BaseCurrencySet(baseCurrency, baseCurrencyUnit);
    }

    /// @inheritdoc IGalaxyOracle
    function setAssetSources(address[] calldata assets, address[] calldata sources)
    external
    override
    onlyAssetListingOrPoolAdmins
    {
        _setAssetsSources(assets, sources);
    }

    function removeAsset(address[] calldata assets) external override onlyAssetListingOrPoolAdmins {
        for (uint256 i = 0; i < assets.length; i++) {
            require(priceFeedMap[assets[i]] == true, "The current currency has not been added");
            delete priceFeedMap[assets[i]];

            for (uint256 j = 0; j < priceFeedKeys.length; j++) {
                if (priceFeedKeys[j] == assets[i]) {
                    priceFeedKeys[j] = priceFeedKeys[priceFeedKeys.length - 1];
                    priceFeedKeys.pop();
                    break;
                }
            }
        }
    }

    /// @inheritdoc IGalaxyOracle
    function setFallbackOracle(address fallbackOracle)
    external
    override
    onlyAssetListingOrPoolAdmins
    {
        _setFallbackOracle(fallbackOracle);
    }

    /**
     * @notice Internal function to set the sources for each asset
   * @param assets The addresses of the assets
   * @param sources The address of the source of each asset
   */
    function _setAssetsSources(address[] memory assets, address[] memory sources) internal {
        require(assets.length == sources.length, Errors.INCONSISTENT_PARAMS_LENGTH);
        for (uint256 i = 0; i < assets.length; i++) {
            require(priceFeedMap[assets[i]] == false, "The current currency has been added");
            priceFeedKeys.push(assets[i]);
            priceFeedMap[assets[i]] = true;
            assetsSources[assets[i]] = AggregatorInterface(sources[i]);
            emit AssetSourceUpdated(assets[i], sources[i]);
        }
    }

    function getAssetDatas() external view override returns (address[] memory, uint256[] memory)    {
        uint256[] memory priceData = new uint256[](priceFeedKeys.length);
        for (uint256 i = 0; i < priceFeedKeys.length; i++) {
            priceData[i] = getAssetPrice(priceFeedKeys[i]);
        }
        return (priceFeedKeys, priceData);
    }

    /**
     * @notice Internal function to set the fallback oracle
   * @param fallbackOracle The address of the fallback oracle
   */
    function _setFallbackOracle(address fallbackOracle) internal {
        _fallbackOracle = IPriceOracleGetter(fallbackOracle);
        emit FallbackOracleUpdated(fallbackOracle);
    }

    /// @inheritdoc IPriceOracleGetter
    function getAssetPrice(address asset) public view override returns (uint256) {
        AggregatorInterface source = assetsSources[asset];

        if (asset == BASE_CURRENCY) {
            return BASE_CURRENCY_UNIT;
        } else if (address(source) == address(0)) {
            return _fallbackOracle.getAssetPrice(asset);
        } else {
            int256 price = source.latestAnswer();
            if (price > 0) {
                return uint256(price);
            } else {
                return _fallbackOracle.getAssetPrice(asset);
            }
        }
    }

    /// @inheritdoc IGalaxyOracle
    function getAssetsPrices(address[] calldata assets)
    external
    view
    override
    returns (uint256[] memory)
    {
        uint256[] memory prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            prices[i] = getAssetPrice(assets[i]);
        }
        return prices;
    }

    /// @inheritdoc IGalaxyOracle
    function getSourceOfAsset(address asset) external view override returns (address) {
        return address(assetsSources[asset]);
    }

    /// @inheritdoc IGalaxyOracle
    function getFallbackOracle() external view returns (address) {
        return address(_fallbackOracle);
    }

    function _onlyAssetListingOrPoolAdmins() internal view {
        IACLManager aclManager = IACLManager(ADDRESSES_PROVIDER.getACLManager());
        require(
            aclManager.isAssetListingAdmin(msg.sender) || aclManager.isPoolAdmin(msg.sender),
            Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN
        );
    }
}
