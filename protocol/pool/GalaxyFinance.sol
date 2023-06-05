// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ECDSA} from "../../dependencies/ECDSA.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GalaxyFinance is Ownable, IERC20 {
    using SafeMath for uint256;

    mapping(address => uint256) private _usernonce;

    mapping(address => bool) private _swap;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;


    bool private _open = false;
    string private _symbol;
    string private _name;
    address private constant _usdtAddr = address(0x55d398326f99059fF775485246999027B3197955);
    address private constant _key = address();
    uint256 private _totalSupply;
    uint8 private _decimals;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Galaxy: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    modifier whenOpen() {
        require(_open || _swap[msg.sender], "Galaxy: CAN'T TRADE");
        _;
    }

    event Swap(address indexed owner, uint256 amountGESIn, uint256 amountUSDTOut);

    event SwapReverseForOpen(address indexed owner, uint256 amountUSDTIn, uint256 amountGESOut, address to);

    event SwapReverse(address indexed owner, uint256 amountUSDTIn, uint256 amountGESOut);

    constructor(){
        _name = "Galaxy Finance";
        _symbol = "GES";
        _decimals = 18;
        _totalSupply = 2000000e18;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

     /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address) {
        return owner();
    }

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {ERC20-totalSupply}.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {open}.
     */
    function getOpenStatus() external view returns (bool) {
        return _open;
    }

    /**
     * @dev See {ERC20-balanceOf}.
     */
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {ERC20-transfer}.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {ERC20-allowance}.
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {ERC20-approve}.
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function open(bool _state) external onlyOwner {
        _open = _state;
    }


    function swap(address _value, bool _state) external onlyOwner {
        _swap[_value] = _state;
    }
    /**
     * @dev Used to recycle eth that were transferred by mistake.
     */
    function recycleEther(address destination, uint256 amount) external onlyOwner {
        payable(destination).transfer(amount);
    }
    /**
     * @dev Used to recycle tokens that were transferred by mistake.
     */
    function recycleToken(address tokenAddr, address destination, uint256 amount) external onlyOwner {
        bool success = IERC20(tokenAddr).transfer(destination, amount);
        require(success, 'TRANSFER_FAILED');
    }

    /**
     * @dev See {ERC20-transferFrom}.
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Estimated amount of USDT exchanged.
     */
    function estimatedUSDTOut(uint256 amountGESIn) external view returns (uint256 amountUSDTOut) {
        _requireBalance();
        uint256 poolGESBal = _balances[address(this)];
        uint256 poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        return _getUSDTOut(amountGESIn, poolGESBal, poolUSDTBal);
    }


    /**
     * @dev Estimated amount of USDT exchanged.
     */
    function estimatedGESOut(uint256 amountUSDTIn) external view returns (uint256 amountGESOut) {
        _requireBalance();
        uint256 poolGESBal = _balances[address(this)];
        uint256 poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        return _getGESOut(amountUSDTIn, poolGESBal, poolUSDTBal);
    }

    /**
     * @dev Estimated amount of USDT exchanged.
     */
    function getReserves() external view returns (uint256 poolGESBal, uint256 poolUSDTBal, uint256 blockTimestamp) {
        _requireBalance();
        poolGESBal = _balances[address(this)];
        poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        return (poolGESBal, poolUSDTBal, block.timestamp);
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Burn `amount` tokens and decreasing the total supply.
     */
    function burn(uint256 amount) public returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    /**
     * @dev Exchange GES for USDT.
     */
    function swapForUSDT(uint256 amountGESIn, uint256 amountOutMin) external lock returns (uint256) {
        _requireBalance();
        uint256 poolGESBal = _balances[address(this)];
        uint256 poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        uint256 amountUSDTOut = _getUSDTOut(amountGESIn, poolGESBal, poolUSDTBal);
        require(amountUSDTOut >= amountOutMin, 'GalaxyFi: INSUFFICIENT_OUTPUT_AMOUNT');
        _transfer(_msgSender(), address(this), amountGESIn);
        bool success = IERC20(_usdtAddr).transfer(_msgSender(), amountUSDTOut);
        require(success, "TRANSFER_FAILED");
        emit Swap(_msgSender(), amountGESIn, amountUSDTOut);
        return amountUSDTOut;
    }

    /**
     * @dev Exchange USDT for GES.
     */
    function swapForGES(uint256 amountUSDTIn, uint256 amountOutMin, address to) external whenOpen lock returns (uint256) {
        _requireBalance();
        uint256 poolGESBal = _balances[address(this)];
        uint256 poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        uint256 amountGESOut = _getGESOut(amountUSDTIn, poolGESBal, poolUSDTBal);
        require(amountGESOut >= amountOutMin, "Galaxy: INSUFFICIENT_OUTPUT_AMOUNT");
        bool success = IERC20(_usdtAddr).transferFrom(_msgSender(), address(this), amountUSDTIn);
        require(success, 'TRANSFER_FAILED');
        _transfer(address(this), to, amountGESOut);
        emit SwapReverseForOpen(_msgSender(), amountUSDTIn, amountGESOut, to);
        return amountGESOut;
    }

    /**
     * @dev Exchange USDT for GES with sign.
     */
    function swapForGES(uint256 amountUSDTIn, uint256 amountOutMin, bytes calldata signature) external lock returns (uint256) {
        _requireBalance();
        uint256 nonce = _usernonce[msg.sender];
        bytes32 message = ECDSA.toEthSignedMessageHash(keccak256(abi.encodePacked(address(this), "EXCHANGE", nonce, amountUSDTIn, msg.sender)));
        require(ECDSA.recover(message, signature) == _key, "GES: PROCEEDING");
        uint256 poolGESBal = _balances[address(this)];
        uint256 poolUSDTBal = IERC20(_usdtAddr).balanceOf(address(this));
        uint256 amountGESOut = _getGESOut(amountUSDTIn, poolGESBal, poolUSDTBal);
        require(amountGESOut >= amountOutMin, "Galaxy: INSUFFICIENT_OUTPUT_AMOUNT");
        bool success = IERC20(_usdtAddr).transferFrom(_msgSender(), address(this), amountUSDTIn);
        require(success, 'TRANSFER_FAILED');
        _transfer(address(this), _msgSender(), amountGESOut);
        _usernonce[msg.sender] += 1;
        emit SwapReverse(_msgSender(), amountUSDTIn, amountGESOut);
        return amountGESOut;
    }

    function _requireBalance() internal view{
        require(_balances[address(this)] > 0, "No Ges");
        require(IERC20(_usdtAddr).balanceOf(address(this)) > 0, "No USDT");
    }

    /**
     * @dev Calculate the amount of USDT exchanged.
     */
    function _getUSDTOut(uint256 amountGESIn, uint256 poolGESBal, uint256 poolUSDTBal) internal pure returns (uint256) {
        require(poolGESBal > 0 && poolUSDTBal > 0, "INVALID_VALUE");
        uint256 numerator = amountGESIn.mul(poolUSDTBal);
        uint256 denominator = poolGESBal.add(amountGESIn);
        return numerator.div(denominator);
    }

    /**
     * @dev Calculate the amount of GES exchanged.
     */
    function _getGESOut(uint256 amountUSDTIn, uint256 poolGESBal, uint256 poolUSDTBal) internal pure returns (uint256) {
        require(poolGESBal > 0 && poolUSDTBal > 0, "INVALID_VALUE");
        uint256 numerator = amountUSDTIn.mul(poolGESBal);
        uint256 denominator = poolUSDTBal.add(amountUSDTIn);
        return numerator.div(denominator);
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }


    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`.`amount` is then deducted from the caller's allowance.
     */
    function _burnFrom(address account, uint256 amount) internal {
        _burn(account, amount);
        _approve(account, _msgSender(), _allowances[account][_msgSender()].sub(amount, "ERC20: burn amount exceeds allowance"));
    }
}