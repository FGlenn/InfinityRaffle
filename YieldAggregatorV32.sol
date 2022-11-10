// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IPoolAddressesProvider} from "../dependencies/IPoolAddressesProvider.sol";
import {IPool} from "../dependencies/IPool.sol";
import {WethInterface} from "../dependencies/WethInterface.sol";
import {Ownable} from "../dependencies/Ownable.sol";
import {ReentrancyGuard} from "../dependencies/ReentrancyGuard.sol";

error YieldAggregatorV32__AddressHasNoIndex(address inserted);
error YieldAggregatorV32__AddressHasZeroBalance();
error YieldAggregatorV32__AddressAlreadyEntered(address player);

contract YieldAggregatorV32 is Ownable, ReentrancyGuard {
    //////// Variables ////////
    IPoolAddressesProvider public ADDRESS_PROVIDER;
    IPool public POOL;
    WethInterface public WETH;
    address payable[] private s_players;
    mapping(address => uint256) s_addressToAmountFunded;
    mapping(address => uint256) s_addressToAmountPrizes;
    bool private _paused;

    //////// Events ////////
    event PlayerWithdrawn(address player, uint256 value);
    event PlayerEntered(address player, uint256 value);
    event received(string funct, address sender, uint256 value, bytes data);

    constructor(address _provider, address payable _weth) {
        ADDRESS_PROVIDER = IPoolAddressesProvider(_provider);
        POOL = IPool(ADDRESS_PROVIDER.getPool());
        WETH = WethInterface(_weth);
    }

    ////// Main functions ////////
    function enterPlayer(uint256 _value) internal {
        // For this contract each address can join once.
        if (getHasIndex(msg.sender)) {
            revert YieldAggregatorV32__AddressAlreadyEntered(msg.sender);
        }
        // Stores the player and it's deposit in the contract.
        s_players.push(payable(msg.sender));
        s_addressToAmountFunded[msg.sender] += _value;
        exchangeToWeth(_value);
        approveWeth(_value);
        depositToAave(_value);
        emit PlayerEntered(msg.sender, _value);
    }

    // the "nonReentrant" modifier is a pattern that can be used to avoid reentrancy attacks.
    function withdrawPlayer() public nonReentrant {
        // This function withdrawls the amount deposited and the prize(s), if the player has won any, in a single transaction.
        uint256 balance = s_addressToAmountFunded[msg.sender] +
            s_addressToAmountPrizes[msg.sender];
        if (balance == 0) {
            revert YieldAggregatorV32__AddressHasZeroBalance();
        }

        // Deletes the player out of the mappings
        delete s_addressToAmountFunded[msg.sender];
        delete s_addressToAmountPrizes[msg.sender];

        // Removes the player from the players array.
        // 1. Gets the index of the withdrawing player.
        uint256 indexPlayer = getIndexOfAddress(msg.sender);
        // 2. Gets the index of the last player in the array.
        uint256 indexLastPlayer = s_players.length - 1;
        // 3. Gets the address of the last player in the array.
        address payable lastPlayer = s_players[indexLastPlayer];
        // 4. Moves the address of the last player to the spot of the withdrawing player.
        s_players[indexPlayer] = lastPlayer;
        // 5. The last player now has two spots in the array. Pop deletes the last spot, which is a duplicate and reduces the array length by one.
        s_players.pop();

        // Withdrawls WETH from the Aave contract
        POOL.withdraw(address(WETH), balance, address(this));

        // Coverts WETH to ETH 1:1 to the ETH sent. Afterwards sends the ETH to the withdrawing player.
        withdrawEth(msg.sender, balance);
        emit PlayerWithdrawn(msg.sender, balance);
    }

    //////// Sub functions ////////
    function withdrawEth(address _player, uint256 _balance) internal {
        exchangeToEth(_balance);
        (bool success, ) = _player.call{value: _balance}(new bytes(0));
        require(success, "Failed");
    }

    function exchangeToWeth(uint256 _value) internal {
        // Coverts ETH to WETH 1:1 to the ETH sent.
        WETH.deposit{value: _value}();
    }

    function exchangeToEth(uint256 _balance) internal {
        // Approves WETH to be send.
        bool success = WETH.approve(address(this), _balance);
        require(success, "Failed approval");
        // Coverts WETH to ETH 1:1 to the ETH sent.
        WETH.withdraw(_balance);
    }

    function approveWeth(uint256 _value) internal {
        // Approves WETH to be send.
        WETH.approve(address(POOL), _value);
    }

    function depositToAave(uint256 _value) internal {
        // Deposits WETH in the Aave lending pool.
        POOL.deposit(address(WETH), _value, address(this), 0);
    }

    fallback() external payable {}

    receive() external payable {}

    //////// view functions /////////

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getAddressAtIndex(uint256 _index) public view returns (address) {
        return s_players[_index];
    }

    // looping through an array using a memory variable to safe gas instead of taking an excessive storage slot for  "mapping(uint256 => address) s_addressToAmountFunded;"
    function getIndexOfAddress(address _address) public view returns (uint256) {
        address payable[] memory players = s_players;
        uint256 index;
        for (
            uint256 playerIndex = 0;
            playerIndex < players.length;
            playerIndex++
        ) {
            address payable player = players[playerIndex];
            if (player == _address) {
                index = playerIndex;
            }
        }
        if (players[index] != _address) {
            revert YieldAggregatorV32__AddressHasNoIndex(_address);
        }
        return index;
    }

    // looping through an array using a memory variable to safe gas instead of taking an excessive storage slot for  "mapping(uint256 => address) s_addressToAmountFunded;"
    function getHasIndex(address _address) public view returns (bool) {
        address payable[] memory players = s_players;
        bool hasIndex = false;
        for (
            uint256 playerIndex = 0;
            playerIndex < players.length;
            playerIndex++
        ) {
            address payable player = players[playerIndex];
            if (player == _address) {
                hasIndex = true;
            }
        }
        return hasIndex;
    }

    function getPlayerDeposited(address _address)
        public
        view
        returns (uint256)
    {
        return s_addressToAmountFunded[_address];
    }

    function getPlayerPrizes(address _address) public view returns (uint256) {
        return s_addressToAmountPrizes[_address];
    }

    function getPlayerBalance(address _playerAddress)
        public
        view
        returns (uint256)
    {
        return (getPlayerDeposited(_playerAddress) +
            getPlayerPrizes(_playerAddress));
    }

    // Loops through all deposits of all players and adds them up.
    function getTotalDeposited() public view returns (uint256) {
        uint256 totalDeposits = 0;
        address payable[] memory players = s_players;
        for (
            uint256 playerIndex = 0;
            playerIndex < players.length;
            playerIndex++
        ) {
            address player = players[playerIndex];
            totalDeposits += s_addressToAmountFunded[player];
        }
        return totalDeposits;
    }

    // Loops through all prizes won of all players and adds them up.
    function getTotalWonPrizes() public view returns (uint256) {
        uint256 totalPrizes = 0;
        address payable[] memory players = s_players;
        for (
            uint256 playerIndex = 0;
            playerIndex < players.length;
            playerIndex++
        ) {
            address player = players[playerIndex];
            totalPrizes += s_addressToAmountPrizes[player];
        }
        return totalPrizes;
    }

    function getYieldBalance() public view returns (uint256) {
        return getUserAccountData() - getTotalDeposited() - getTotalWonPrizes();
    }

    function getUserAccountData() public view returns (uint256) {
        (uint256 totalCollateralBase, , , , , ) = POOL.getUserAccountData(
            address(this)
        );
        return totalCollateralBase * 2500000;
    }
}
