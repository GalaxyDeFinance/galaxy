// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.10;

import {Ownable} from '../../dependencies/openzeppelin/contracts/Ownable.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {InitializableImmutableAdminUpgradeabilityProxy} from '../libraries/galaxy-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol';

/**
 * @title PoolAddressesProvider
 *
 * @notice Main registry of addresses part of or connected to the protocol, including permissioned roles
 * @dev Acts as factory of proxies and admin of those, so with right to change its implementations
 * @dev Owned by the Galaxy Governance
 **/
contract PoolAddressesProvider is Ownable, IPoolAddressesProvider {
    // Identifier of the Galaxy Market
    string private _marketId;

    // Map of registered addresses (identifier => registeredAddress)
    mapping(bytes32 => address) private _addresses;
    mapping(address => bool) private isPool;

    // Main identifiers
    bytes32 private constant POOL = 'POOL';
    bytes32 private constant PRICE_ORACLE = 'PRICE_ORACLE';
    bytes32 private constant ACL_MANAGER = 'ACL_MANAGER';
    bytes32 private constant ACL_ADMIN = 'ACL_ADMIN';

    /**
     * @dev Constructor.
   * @param marketId The identifier of the market.
   * @param owner The owner address of this contract.
   */
    constructor(string memory marketId, address owner) {
        _setMarketId(marketId);
        transferOwnership(owner);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getMarketId() external view override returns (string memory) {
        return _marketId;
    }

    /// @inheritdoc IPoolAddressesProvider
    function setMarketId(string memory newMarketId) external override onlyOwner {
        _setMarketId(newMarketId);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getAddress(bytes32 id) public view override returns (address) {
        return _addresses[id];
    }

    /// @inheritdoc IPoolAddressesProvider
    function setAddress(bytes32 id, address newAddress) external override onlyOwner {
        address oldAddress = _addresses[id];
        _addresses[id] = newAddress;
        emit AddressSet(id, oldAddress, newAddress);
    }
    /// @inheritdoc IPoolAddressesProvider
    function setPoolValid(address[] memory poolAddresses) external override onlyOwner {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            require(poolAddresses[i] != address(0), "Not Valid address");
            isPool[poolAddresses[i]] = true;
            emit SetPoolValid(poolAddresses);
        }
    }
    /// @inheritdoc IPoolAddressesProvider
    function isValidPool(address poolAddress) external view override returns (bool){
        return isPool[poolAddress];
    }

    /// @inheritdoc IPoolAddressesProvider
    function setAddressAsProxy(bytes32 id, address newImplementationAddress)
    external
    override
    onlyOwner
    {
        address proxyAddress = _addresses[id];
        address oldImplementationAddress = _getProxyImplementation(id);
        _updateImpl(id, newImplementationAddress);
        emit AddressSetAsProxy(id, proxyAddress, oldImplementationAddress, newImplementationAddress);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPool() external view override returns (address) {
        return getAddress(POOL);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPoolImpl(address newPoolImpl) external override onlyOwner {
        address oldPoolImpl = _getProxyImplementation(POOL);
        _updateImpl(POOL, newPoolImpl);
        emit PoolUpdated(oldPoolImpl, newPoolImpl);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPool(address newPoolAddress) external override onlyOwner {
        address oldPool = _addresses[POOL];
        _addresses[POOL] = newPoolAddress;
        emit PoolUpdated(oldPool, newPoolAddress);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getPriceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setPriceOracle(address newPriceOracle) external override onlyOwner {
        address oldPriceOracle = _addresses[PRICE_ORACLE];
        _addresses[PRICE_ORACLE] = newPriceOracle;
        emit PriceOracleUpdated(oldPriceOracle, newPriceOracle);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getACLManager() external view override returns (address) {
        return getAddress(ACL_MANAGER);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setACLManager(address newAclManager) external override onlyOwner {
        address oldAclManager = _addresses[ACL_MANAGER];
        _addresses[ACL_MANAGER] = newAclManager;
        emit ACLManagerUpdated(oldAclManager, newAclManager);
    }

    /// @inheritdoc IPoolAddressesProvider
    function getACLAdmin() external view override returns (address) {
        return getAddress(ACL_ADMIN);
    }

    /// @inheritdoc IPoolAddressesProvider
    function setACLAdmin(address newAclAdmin) external override onlyOwner {
        address oldAclAdmin = _addresses[ACL_ADMIN];
        _addresses[ACL_ADMIN] = newAclAdmin;
        emit ACLAdminUpdated(oldAclAdmin, newAclAdmin);
    }


    /**
     * @notice Internal function to update the implementation of a specific proxied component of the protocol.
   * @dev If there is no proxy registered with the given identifier, it creates the proxy setting `newAddress`
   *   as implementation and calls the initialize() function on the proxy
   * @dev If there is already a proxy registered, it just updates the implementation to `newAddress` and
   *   calls the initialize() function via upgradeToAndCall() in the proxy
   * @param id The id of the proxy to be updated
   * @param newAddress The address of the new implementation
   **/
    function _updateImpl(bytes32 id, address newAddress) internal {
        address proxyAddress = _addresses[id];
        InitializableImmutableAdminUpgradeabilityProxy proxy;
        bytes memory params = abi.encodeWithSignature('initialize(address)', address(this));

        if (proxyAddress == address(0)) {
            proxy = new InitializableImmutableAdminUpgradeabilityProxy(address(this));
            _addresses[id] = proxyAddress = address(proxy);
            proxy.initialize(newAddress, params);
            emit ProxyCreated(id, proxyAddress, newAddress);
        } else {
            proxy = InitializableImmutableAdminUpgradeabilityProxy(payable(proxyAddress));
            proxy.upgradeToAndCall(newAddress, params);
        }
    }

    /**
     * @notice Updates the identifier of the Galaxy market.
   * @param newMarketId The new id of the market
   **/
    function _setMarketId(string memory newMarketId) internal {
        string memory oldMarketId = _marketId;
        _marketId = newMarketId;
        emit MarketIdSet(oldMarketId, newMarketId);
    }

    /**
     * @notice Returns the the implementation contract of the proxy contract by its identifier.
   * @dev It returns ZERO if there is no registered address with the given id
   * @dev It reverts if the registered address with the given id is not `InitializableImmutableAdminUpgradeabilityProxy`
   * @param id The id
   * @return The address of the implementation contract
   */
    function _getProxyImplementation(bytes32 id) internal returns (address) {
        address proxyAddress = _addresses[id];
        if (proxyAddress == address(0)) {
            return address(0);
        } else {
            address payable payableProxyAddress = payable(proxyAddress);
            return InitializableImmutableAdminUpgradeabilityProxy(payableProxyAddress).implementation();
        }
    }
}
