// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// VRFv2Consumer address 0xcBa1F3cfDe49DA14303b86FE9123E760859c01f5

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RSP_game is ReentrancyGuard, VRFConsumerBase {
    using SafeERC20 for IERC20Metadata;
    using SafeMath for uint256;

    bytes32 internal keyHash;
    uint256 internal fee;

    address public constant zeroAddress = 0x0000000000000000000000000000000000000000;
    address public owner;
    address public nftContractForFreeFee;

    uint256 public FEEbyBet = 100; // 1 of 1000000 by bet;
    uint256 public blocksToGameOver;
    uint256 public randomResult;

    struct GameSolo {
        bool isPlayed;
        uint8 choice;
        address player;
        address token;
        uint256 balance;
    }
    mapping(bytes32 => GameSolo) private commitments;
    mapping(address => uint256) public balanceP2PbyToken;

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

    event GameP2CisPlayed(address indexed player, uint256 amount, uint8 playerChoice, uint8 contractChoice, string result);
    event TransferedOwnership(address indexed fromAddr, address toAddr);
    event AddressVotedToWithdraw(address indexed addr, bool vote);
    event FeeChanged(uint256 oldFee, uint256 newFee, address owner);
    event NftContractChanged(address oldNFT, address newNFT, address owner);
    event GameP2PisOpen(address indexed player, address token);
    event GameP2PisPlayed(address indexed player_1, address indexed player_2);
    event GameP2PisClosed(address indexed winner, address token);
    event GameP2PisCancelled(address indexed creator, address token);

    constructor(
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash,
        uint256 _fee
    )
    VRFConsumerBase(_vrfCoordinator, _link)
    payable {
        owner = msg.sender;
        blocksToGameOver = 2 * 60 * 20; // 2 hour
        keyHash = _keyHash;
        fee = _fee;
    }


    // === Player to Contract game === start
    function getRandomNumber() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        return requestRandomness(keyHash, fee);
    }

    function playP2CbyBNB(uint8 _choice) public payable nonReentrant{
        require(_choice < 3, "Choose rock scissors or paper");
        require(msg.value <= maxBetP2CbyBNB(), "Balance is not enough");
        require(msg.value >= 10**14, "Your bet must be greater");

        bytes32 requestId = requestRandomness(keyHash, fee);
        commitments[requestId] = GameSolo(false, _choice, msg.sender, zeroAddress, msg.value);
    }
    
    function playP2CbyToken(uint8 _choice, address _token, uint256 _amount) public nonReentrant{
        require(_choice < 3, "Choose rock scissors or paper");
        require(_amount <= maxBetP2CbyToken(_token), "Your bet should be less than contract balance");

        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(msg.sender) >= _amount, "Your balance is not enough");
        pay(msg.sender, address(this), _token, _amount);

        bytes32 requestId = requestRandomness(keyHash, fee);
        commitments[requestId] = GameSolo(false, _choice, msg.sender, _token, _amount);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        GameSolo storage game = commitments[requestId];
        require(!game.isPlayed, "Game is played");
        game.isPlayed = true;
        uint8 contractChoice = uint8(randomness % 3);
        string memory result;

        uint256 feeAmount = calculateFee(msg.value);
        if (contractChoice == game.choice) {
            uint256 transferAmount = (game.balance).sub(feeAmount);
            pay(address(this), game.player, game.token, transferAmount);
            result = "Draw";
        } else if (game.choice == 0 && contractChoice == 1
                || game.choice == 1 && contractChoice == 2
                || game.choice == 2 && contractChoice == 0){
            uint256 transferAmount = (msg.value.mul(2)).sub(feeAmount);
            pay(address(this), game.player, game.token, transferAmount);
            result = "Win";
        } else {
            result = "Fail";
        }
        emit GameP2CisPlayed(game.player, game.balance, game.choice, contractChoice, result);
    }
    // === Player to Contract game === end

    // === Player to Player game === start
    function createHashForGame(uint8 _choice, uint256 _secretCode) public view returns(uint256) {
        require(_choice < 3, "Choose rock scissors or paper");
        return uint256(keccak256(abi.encodePacked(_choice, _secretCode, msg.sender)));
    }

    function getFirstOpenGameByToken(address token) public view returns(bool, uint256) {
        uint256 timeStamp = block.timestamp;
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if (gamesP2P[i].token == token && gamesP2P[i].player_1 == msg.sender && gamesP2P[i].player_2 == zeroAddress && gamesP2P[i].timeGameOver < timeStamp) {
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
        require(msg.value >= 10**14, "Your bet must be greater");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created game, wait or cancel it");
        gamesP2P.push(Game( zeroAddress, msg.value, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[zeroAddress] = balanceP2PbyToken[zeroAddress].add(msg.value);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    function createGameP2PbyToken(address _token, uint256 _amount, uint256 _hashBit) public payable nonReentrant {
        require(_amount >= 0, "Your bet must be greater");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created game, wait or cancel it");
        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(msg.sender) >= _amount, "Not enough tokens for game");
        pay(msg.sender, address(this), _token, _amount);
        gamesP2P.push(Game( _token, _amount, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(_amount);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    function playFirstOpenGameP2P(uint8 _choice, address _token) public payable nonReentrant {
        require(_choice < 3, "Choose rock scissors or paper");
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
        require(_choice < 3, "Choose rock scissors or paper");
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

    function playOpenGameByIndex(uint8 _choice, uint256 index) public payable nonReentrant {
        require(_choice < 3, "Choose rock scissors or paper");    
        require(gamesP2P[index].player_2 != zeroAddress 
            && gamesP2P[index].player_2 == zeroAddress 
            && gamesP2P[index].timeGameOver < block.timestamp , "Game is not found");
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
        require(_choice < 3, "Choose rock scissors or paper");
        (bool isPlayer_1, uint256 i) = getPlayedGame(msg.sender);
        uint256 feeAmount = calculateFee(gamesP2P[i].balance);
        if (isPlayer_1) {
            require(gamesP2P[i].hashChoice_1 == createHashForGame(_choice, secret), "Incorrect data");
            balanceP2PbyToken[gamesP2P[i].token] = balanceP2PbyToken[gamesP2P[i].token].sub(gamesP2P[i].balance).sub(gamesP2P[i].balance);
            if (_choice == gamesP2P[i].choice_2 || gamesP2P[i].player_1 == gamesP2P[i].player_2){
                gamesP2P[i].winner = address(this);
                uint256 transferAmount = (gamesP2P[i].balance).sub(feeAmount);
                pay(address(this), gamesP2P[i].player_1, gamesP2P[i].token, transferAmount); 
                pay(address(this), gamesP2P[i].player_2, gamesP2P[i].token, transferAmount);       
            } else if (_choice == 0 && gamesP2P[i].choice_2 == 1
                    || _choice == 1 && gamesP2P[i].choice_2 == 2
                    || _choice == 2 && gamesP2P[i].choice_2 == 0){
                gamesP2P[i].winner = gamesP2P[i].player_1;
                uint256 transferAmount = (gamesP2P[i].balance).mul(2).sub(feeAmount);
                pay(address(this), gamesP2P[i].player_1, gamesP2P[i].token, transferAmount);
            } else {
                gamesP2P[i].winner = gamesP2P[i].player_2;
                uint256 transferAmount = (gamesP2P[i].balance).mul(2).sub(feeAmount);
                pay(address(this), gamesP2P[i].player_2, gamesP2P[i].token, transferAmount);
            }
        } else {
            require(gamesP2P[i].timeGameOver >= block.timestamp, "Wait until the first player confirms his bet");
            balanceP2PbyToken[gamesP2P[i].token] = balanceP2PbyToken[gamesP2P[i].token].sub(gamesP2P[i].balance).sub(gamesP2P[i].balance);
            gamesP2P[i].winner = gamesP2P[i].player_2;
            uint256 transferAmount = (gamesP2P[i].balance).mul(2).sub(feeAmount);
            pay(address(this), gamesP2P[i].player_2, gamesP2P[i].token, transferAmount);
        }
        emit GameP2PisClosed(gamesP2P[i].winner, gamesP2P[i].token); 
    }

    function cancelUnplayedGame() public nonReentrant {
        (bool gameIsReady, uint256 i) = getOpenGameByCreator(msg.sender);
        require(gameIsReady, "You are not player or game is not found");
        require(gamesP2P[i].timeGameOver >= block.timestamp, "Wait until game time is over");
        balanceP2PbyToken[gamesP2P[i].token] = balanceP2PbyToken[gamesP2P[i].token].sub(gamesP2P[i].balance);
        gamesP2P[i].player_2 = gamesP2P[i].player_1;
        gamesP2P[i].winner = gamesP2P[i].player_1;
        uint256 transferAmount = (gamesP2P[i].balance);
        pay(address(this), gamesP2P[i].player_1, gamesP2P[i].token, transferAmount);
        emit GameP2PisCancelled(gamesP2P[i].winner, gamesP2P[i].token); 
    }
    // === Player to Player game === end

    // === Only for Owners === start
    modifier onlyOwner{
        require(msg.sender == owner, "You are not owner!");
        _;
    }
    
    function setFee(uint256 _fee) public onlyOwner {
        emit FeeChanged (FEEbyBet, _fee, msg.sender);
        FEEbyBet = fee;
    }

    function setNftContractForFreeFee(address _address) public onlyOwner {
        emit NftContractChanged(nftContractForFreeFee, _address, msg.sender);
        nftContractForFreeFee = _address;
    }

    function setBlocksToGameOver(uint256 blocks) public onlyOwner {
        blocksToGameOver = blocks;
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function transferOwnership (address newAddress) public onlyOwner {
        require(!isContract(newAddress), "Contract cannot be the owner");
        emit TransferedOwnership(msg.sender, newAddress);
    }

    function withdraw() public onlyOwner {
        require(address(this).balance > balanceP2PbyToken[zeroAddress], "Balance is too small for withdrawal");
        uint256 amountToWithdraw = (address(this).balance).sub(balanceP2PbyToken[zeroAddress]);
        pay(address(this), msg.sender, zeroAddress, amountToWithdraw);
    }

    function withdrawTokens(address _token) external onlyOwner nonReentrant {
        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(address(this)) > balanceP2PbyToken[_token], "Balance is too small for withdrawal");
        uint256 amountToWithdraw = (token.balanceOf(address(this)).sub(balanceP2PbyToken[_token]));
        pay(address(this), msg.sender, _token, amountToWithdraw);
    }
    // === Only for Owners === end

    // === Helpers === start
    function maxBetP2CbyBNB() public view returns(uint256) {
        return address(this).balance.sub(balanceP2PbyToken[zeroAddress]);
    }

    function maxBetP2CbyToken(address _token) public view returns(uint256) {
        IERC20Metadata token = IERC20Metadata(_token);
        return token.balanceOf(address(this)).sub(balanceP2PbyToken[_token]);
    }

    function pay(address _from, address _to, address _token, uint256 _amount) internal {
        if (_token == zeroAddress && _from == address(this)){
            payable(_to).transfer(_amount);
        } else {
            IERC20Metadata token = IERC20Metadata(_token);
            token.safeTransferFrom(_from, _to, _amount);
        }
    }

    function calculateFee(uint256 amount) public view returns (uint256) {
        return IERC721(nftContractForFreeFee).balanceOf(msg.sender) > 0 ? 0 : amount.mul(FEEbyBet).div(1000000);
    }
    // === Helpers === end

    receive() external payable {

    }
}