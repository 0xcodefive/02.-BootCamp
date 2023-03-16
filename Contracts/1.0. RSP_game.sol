// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RSP_game is ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;
    using SafeMath for uint256;

    address constant zeroAddress = 0x0000000000000000000000000000000000000000;

    uint256 public FEE = 1; // 1 of 1000000 by bet;
    uint256 public blocksToGameOver;
    mapping (address => uint256) public balanceP2PbyToken;

    struct Owner {
        address addr;
        bool confirmedWithdraw;
    }
    Owner[] public owners;

    struct Game {
        address token;
        uint256 balance;
        address player_1;
        address player_2;
        address winner;
        uint256 hashChoice_1;
        uint8 choice_2;
        uint256 timeGameOver;
    }
    Game[] public gamesP2P;

    event GameP2CbyBNBisPlayed(address player, uint256 amount, uint8 choice, uint8 result);
    event TransferedOwnership(address fromAddr, address toAddr);
    event AddressVotedToWithdraw(address addr, bool vote);
    event FeeChanged(uint256 oldFee, uint256 newFee, address owner);
    event GameP2PisOpen(address player, address token);
    event GameP2PisPlayed(address player_1, address player_2);
    event GameP2PisClosed(address winner, address token);

    constructor(address[] memory _owners) payable {
        for(uint i = 0; i < _owners.length; i++) {
            owners.push(Owner(_owners[i], false));        
        }
        blocksToGameOver = 2 * 60 * 20; // 2 hour
    }


    // === Player to Contract game === start
    function gameP2CbyBNB(uint8 _choice) public payable nonReentrant returns (uint8, string memory){
        require(_choice < 3, "Please choose rock scissors or paper");
        require(msg.value <= maxBetP2CbyBNB(), "Balance is not enough for the game");
        require(msg.value >= 10**14, "Your bet must be greater than 0.0001 BNB");

        uint8 result = uint8(uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, _choice)))) % 3;

        emit GameP2CbyBNBisPlayed(msg.sender, msg.value, _choice, result);
        if (result == _choice) {
            uint256 feeAmount = calculateFee(msg.value);
            uint256 transferAmount = (msg.value).sub(feeAmount);
            payable(msg.sender).transfer(transferAmount);
            return (0, "Draw");
        } else if (_choice == 0 && result == 1
                || _choice == 1 && result == 2
                || _choice == 2 && result == 0){
            payable(msg.sender).transfer(msg.value.mul(2));
            return (1, "Win");
        }
        return (2, "Fail");   
    }

    function gameP2CbyToken(uint8 _choice, address _token, uint256 _amount) public payable nonReentrant returns (uint8, string memory){
        require(_choice < 3, "Please choose rock scissors or paper");
        require(_amount <= maxBetP2CbyToken(_token), "Your bet should be less than the contract balance");

        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(msg.sender) >= _amount, "Your bet must be greater than 0.0001 BNB");

        uint8 result = uint8(uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, _choice)))) % 3;
        emit GameP2CbyBNBisPlayed(msg.sender, _amount, _choice, result);

        if (result == _choice) {
            uint256 feeAmount = calculateFee(_amount);
            token.safeTransferFrom(
                msg.sender,
                address(this),
                feeAmount
            );
            return (0, "Draw");
        } else if (_choice == 0 && result == 1
                || _choice == 1 && result == 2
                || _choice == 2 && result == 0){
            token.safeTransferFrom(
                address(this),
                msg.sender,
                _amount
            );
            return (1, "Win");
        }
        token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        return (2, "Fail");   
    }

    function maxBetP2CbyBNB() public view returns(uint256) {
        return address(this).balance.sub(balanceP2PbyToken[zeroAddress]);
    }

    function maxBetP2CbyToken(address _token) public view returns(uint256) {
        IERC20Metadata token = IERC20Metadata(_token);
        return token.balanceOf(address(this)).sub(balanceP2PbyToken[_token]);
    }
    // === Player to Contract game === end

    // === Player to Player game === start
    function createHashForGame(uint8 _choice, uint256 _secretCode) public view returns(uint256) {
        require(_choice < 3, "Please choose rock scissors or paper");
        return uint256(keccak256(abi.encodePacked(_choice, _secretCode, msg.sender)));
    }

    function getFirstOpenGameByToken(address token) public view returns(bool, uint256) {
        uint256 timeStamp = block.timestamp;
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if (gamesP2P[i].token == token && gamesP2P[i].player_2 == zeroAddress && gamesP2P[i].timeGameOver < timeStamp) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function getOpenGameByCreator(address player) public view returns(bool, uint256) {
        uint256 timeStamp = block.timestamp;
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if (gamesP2P[i].player_1 == player && gamesP2P[i].player_2 == zeroAddress && gamesP2P[i].timeGameOver < timeStamp) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function createGameP2PbyBNB(uint256 _hashBit) public payable nonReentrant {
        require(msg.value >= 10**14, "Your bet must be greater than 0.0001 BNB");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created a game, wait or cancel it");
        gamesP2P.push(Game( zeroAddress, msg.value, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[zeroAddress] = balanceP2PbyToken[zeroAddress].add(msg.value);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    function createGameP2PbyToken(address _token, uint256 _amount, uint256 _hashBit) public payable nonReentrant {
        require(_amount >= 0, "Your bet must be greater than zero");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created a game, wait or cancel it");
        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(msg.sender) >= _amount, "Not enough tokens for game");
        token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        gamesP2P.push(Game( _token, _amount, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(_amount);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    function playFirstOpenGameP2P(uint8 _choice, address _token) public payable nonReentrant {
        require(_choice < 3, "Please choose rock scissors or paper");
        (bool gameIsReady, uint256 index) = getFirstOpenGameByToken(_token);
        require(gameIsReady, "Game is not found");
        if (_token == zeroAddress) {
            require(msg.value >= gamesP2P[index].balance, "Not enough BNB for game");
            if (msg.value > gamesP2P[index].balance) {
                payable(msg.sender).transfer((msg.value).sub(gamesP2P[index].balance));
            }
        } else {
            IERC20Metadata token = IERC20Metadata(_token);
            require(token.balanceOf(msg.sender) >= gamesP2P[index].balance, "Not enough tokens for game");
            token.safeTransferFrom(
                msg.sender,
                address(this),
                gamesP2P[index].balance
            );
        }
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(gamesP2P[index].balance);
        gamesP2P[index].player_2 = msg.sender;
        gamesP2P[index].choice_2 = _choice;
        gamesP2P[index].timeGameOver = (block.timestamp).add(blocksToGameOver);
        emit GameP2PisPlayed(gamesP2P[index].player_1, msg.sender);
    }

    function playFirstOpenGameByCreator(uint8 _choice, address _creator) public payable nonReentrant {
        require(_choice < 3, "Please choose rock scissors or paper");
        (bool gameIsReady, uint256 index) = getOpenGameByCreator(_creator);
        require(gameIsReady, "Game is not found");
        address _token = gamesP2P[index].token;
        if (_token == zeroAddress) {
            require(msg.value >= gamesP2P[index].balance, "Not enough BNB for game");
            if (msg.value > gamesP2P[index].balance) {
                payable(msg.sender).transfer((msg.value).sub(gamesP2P[index].balance));
            }
        } else {
            IERC20Metadata token = IERC20Metadata(_token);
            require(token.balanceOf(msg.sender) >= gamesP2P[index].balance, "Not enough tokens for game");
            token.safeTransferFrom(
                msg.sender,
                address(this),
                gamesP2P[index].balance
            );
        }
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(gamesP2P[index].balance);
        gamesP2P[index].player_2 = msg.sender;
        gamesP2P[index].choice_2 = _choice;
        gamesP2P[index].timeGameOver = (block.timestamp).add(blocksToGameOver);
        emit GameP2PisPlayed(gamesP2P[index].player_1, msg.sender);
    }

    function getPlayedGame(address player) public view returns(bool, uint256) {
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if ((gamesP2P[i].player_1 == player || gamesP2P[i].player_2 == player) && gamesP2P[i].player_2 != zeroAddress && gamesP2P[i].winner == zeroAddress) {
                return (gamesP2P[i].player_1 == player, i);
            }
        }
        revert("You are not player or game is not found");
    }

    function closeGameAndGetMoney(uint8 _choice, uint256 secret) public nonReentrant {
        require(_choice < 3, "Please choose rock scissors or paper");
        (bool isPlayer_1, uint256 i) = getPlayedGame(msg.sender);
        if (isPlayer_1) {
            require(gamesP2P[i].hashChoice_1 == createHashForGame(_choice, secret), "Incorrect data");
            balanceP2PbyToken[gamesP2P[i].token] = balanceP2PbyToken[gamesP2P[i].token].sub(gamesP2P[i].balance).sub(gamesP2P[i].balance);
            if (_choice == gamesP2P[i].choice_2 || gamesP2P[i].player_1 == gamesP2P[i].player_2){
                gamesP2P[i].winner = address(this);
                uint256 feeAmount = calculateFee(gamesP2P[i].balance);
                uint256 transferAmount = (gamesP2P[i].balance).sub(feeAmount);
                if (gamesP2P[i].token == zeroAddress) {
                    payable(gamesP2P[i].player_1).transfer(transferAmount);
                    payable(gamesP2P[i].player_2).transfer(transferAmount);
                } else {
                    IERC20Metadata token = IERC20Metadata(gamesP2P[i].token);
                    token.safeTransferFrom(
                        address(this),
                        gamesP2P[i].player_1,
                        transferAmount
                    );
                    token.safeTransferFrom(
                        address(this),
                        gamesP2P[i].player_1,
                        transferAmount
                    );
                }       
            } else if (_choice == 0 && gamesP2P[i].choice_2 == 1
                    || _choice == 1 && gamesP2P[i].choice_2 == 2
                    || _choice == 2 && gamesP2P[i].choice_2 == 0){
                gamesP2P[i].winner = gamesP2P[i].player_1;
                uint256 transferAmount = (gamesP2P[i].balance).mul(2);
                if (gamesP2P[i].token == zeroAddress) {
                    payable(gamesP2P[i].player_1).transfer(transferAmount);
                } else {
                    IERC20Metadata token = IERC20Metadata(gamesP2P[i].token);
                    token.safeTransferFrom(
                        address(this),
                        gamesP2P[i].player_1,
                        transferAmount
                    );
                }
            } else {
                gamesP2P[i].winner = gamesP2P[i].player_2;
                uint256 transferAmount = (gamesP2P[i].balance).mul(2);
                if (gamesP2P[i].token == zeroAddress) {
                    payable(gamesP2P[i].player_2).transfer(transferAmount);
                } else {
                    IERC20Metadata token = IERC20Metadata(gamesP2P[i].token);
                    token.safeTransferFrom(
                        address(this),
                        gamesP2P[i].player_2,
                        transferAmount
                    );
                }
            }
        } else {
            require(gamesP2P[i].timeGameOver >= block.timestamp, "Wait until the first player confirms his bet");
            balanceP2PbyToken[gamesP2P[i].token] = balanceP2PbyToken[gamesP2P[i].token].sub(gamesP2P[i].balance).sub(gamesP2P[i].balance);
            gamesP2P[i].winner = gamesP2P[i].player_2;
            uint256 feeAmount = calculateFee(gamesP2P[i].balance);
            uint256 transferAmount = (gamesP2P[i].balance).sub(feeAmount);
            if (gamesP2P[i].token == zeroAddress) {
                    payable(gamesP2P[i].player_2).transfer(transferAmount);
            } else {
                IERC20Metadata token = IERC20Metadata(gamesP2P[i].token);
                token.safeTransferFrom(
                    address(this),
                    gamesP2P[i].player_2,
                    transferAmount
                );
            }
        }
        emit GameP2PisClosed(gamesP2P[i].winner, gamesP2P[i].token); 
    }

    function calculateFee(uint256 amount) public view returns (uint256) {
        return amount.mul(FEE).div(1000000);
    }

    // === Player to Player game === end

    // === Only for Owners === start
    modifier onlyOwner{
        require(isOwner(msg.sender), "You are not owner!");
        _;
    }
    
    function setFee(uint256 fee) public onlyOwner {
        emit FeeChanged (FEE, fee, msg.sender);
        FEE = fee;
    }

    function setBlocksToGameOver(uint256 blocks) public onlyOwner {
        blocksToGameOver = blocks;
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function isOwner (address _address) internal view returns(bool) {
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i].addr == _address) {
                return true;
            }
        }
        return false;
    }

    function transferOwnership (address newAddress) public onlyOwner {
        require(!isContract(newAddress), "Contract cannot be the owner");
        for(uint i = 0; i < owners.length; i++) {
            if (owners[i].addr == msg.sender) {
                owners[i].addr = newAddress;
                emit TransferedOwnership(msg.sender, newAddress);
                return;
            } 
        }
    }

    function voteToWithdraw (bool vote) public onlyOwner {
        for(uint i = 0; i < owners.length; i++) {
            if (owners[i].addr == msg.sender) {
                require(owners[i].confirmedWithdraw != vote, "You have already voted!");
                owners[i].confirmedWithdraw = vote;
                emit AddressVotedToWithdraw(msg.sender, vote);
                return;
            } 
        }
    }

    function withdraw() public onlyOwner {
        require(address(this).balance > balanceP2PbyToken[zeroAddress].add(21000 * owners.length), "The contract balance is too small for withdrawal");

        for(uint i = 0; i < owners.length; i++) {
            require(owners[i].confirmedWithdraw, "Withdrawal is not possible. Not everyone voted yes");                      
        }

        uint256 balanceToWithdraw = ((address(this).balance).sub(21000).sub(balanceP2PbyToken[zeroAddress])).div(owners.length);  
        for(uint i = 0; i < owners.length; i++) {
            owners[i].confirmedWithdraw = false;
            payable(owners[i].addr).transfer(owners[i].addr == msg.sender ? balanceToWithdraw.add(21000) : balanceToWithdraw);
        }
    }

    function withdrawTokens(address _token) external onlyOwner nonReentrant {
        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(address(this)) > balanceP2PbyToken[_token].add(21000 * owners.length), "The contract balance is too small for withdrawal");
        uint256 balanceToWithdraw = (token.balanceOf(address(this)).sub(balanceP2PbyToken[_token])).div(owners.length);
        for(uint i = 0; i < owners.length; i++) {
            token.safeTransferFrom(
                address(this),
                owners[i].addr,
                balanceToWithdraw
            );
        }
    }
    // === Only for Owners === end

    receive() external payable {

    }
}