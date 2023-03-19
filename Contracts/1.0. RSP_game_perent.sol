// SPDX-License-Identifier: MIT
/************************************************************\
*                                                            *
*      ██████╗ ██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗     *
*     ██╔═████╗╚██╗██╔╝██╔════╝██╔═████╗██╔══██╗██╔════╝     *
*     ██║██╔██║ ╚███╔╝ ██║     ██║██╔██║██║  ██║█████╗       *
*     ████╔╝██║ ██╔██╗ ██║     ████╔╝██║██║  ██║██╔══╝       *
*     ╚██████╔╝██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗     *
*      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝     *
*                                                            *
\************************************************************/

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RSP_game is ReentrancyGuard, VRFConsumerBaseV2, ConfirmedOwner {
    using SafeERC20 for IERC20Metadata;
    using SafeMath for uint256;

    VRFCoordinatorV2Interface COORDINATOR;

    uint16 internal requestConfirmations = 2;
    uint32 internal callbackGasLimit = 200000;
    uint32 internal numWords = 1;
    uint64 internal s_subscriptionId = 2714;
    address internal constant vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 internal constant keyHash = 0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;

    address public constant zeroAddress = 0x0000000000000000000000000000000000000000;
    address public nftContractForFreeFee;

    uint256 public FEEbyBet = 100; // 1 of 1000000 by bet;
    uint256 public blocksToGameOver;

    struct GameSolo {
        bool isPlayed;
        uint8 choice;
        address player;
        address token;
        uint256 balance;
    }
    mapping(uint256 => GameSolo) private commitments;
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

    constructor()
    VRFConsumerBaseV2(0x6A2AAd07396B36Fe02a22b33cf443582f682c82f)
    ConfirmedOwner(msg.sender)
    payable {
        COORDINATOR = VRFCoordinatorV2Interface(
            0x6A2AAd07396B36Fe02a22b33cf443582f682c82f
        );
        blocksToGameOver = 10 * 20; // 1 hour
    }
    
    modifier checkChoice(uint8 _choice) {
        require(_choice < 3, "Choose rock scissors or paper");
        _;
    }

    // === Player to Contract game === start

    // Создание игры с контрактом на BNB
    function playP2CbyBNB(uint8 _choice) public payable nonReentrant checkChoice(_choice){
        require(msg.value <= maxBetP2CbyBNB(), "Balance is not enough");
        require(msg.value >= 10**14, "Your bet must be greater");

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        commitments[requestId] = GameSolo(false, _choice, msg.sender, zeroAddress, msg.value);
    }
    
    // Создание игры с контрактом на пользовательский
    function playP2CbyToken(uint8 _choice, address _token, uint256 _amount) public nonReentrant checkChoice(_choice){
        require(_amount <= maxBetP2CbyToken(_token), "Your bet should be less than contract balance");
        require(pay(msg.sender, address(this), _token, _amount), "Your balance is not enough");

        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        commitments[requestId] = GameSolo(false, _choice, msg.sender, _token, _amount);
    }

    // Колбэк chainlink со случайным значением, определение победитя игры с контрактом
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        GameSolo storage game = commitments[_requestId];
        require(!game.isPlayed, "Game is played");
        game.isPlayed = true;
        uint8 contractChoice = uint8(_randomWords[0] % 3);
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

    // Вспомогательная функция для создания хэша ключа пользователя
    function createHashForGame(uint8 _choice, uint256 _secretCode) public view checkChoice(_choice) returns(uint256) {
        return uint256(keccak256(abi.encodePacked(_choice, _secretCode, msg.sender)));
    }

    // Получаем первую в списке открытую игру с выбранным токеном P2P
    function getFirstOpenGameByToken(address token) public view returns(bool, uint256) {
        uint256 timeStamp = block.timestamp;
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if (gamesP2P[i].token == token && gamesP2P[i].player_1 == msg.sender && gamesP2P[i].player_2 == zeroAddress && gamesP2P[i].timeGameOver < timeStamp) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    // Получаем первую в списке открытую игру с выбранным игроком P2P
    function getOpenGameByCreator(address player) public view returns(bool, uint256) {
        uint256 timeStamp = block.timestamp;
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if (gamesP2P[i].player_1 == player && gamesP2P[i].player_2 == zeroAddress && gamesP2P[i].timeGameOver < timeStamp) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    // Создаем открыю игру P2P на BNB
    function createGameP2PbyBNB(uint256 _hashBit) public payable nonReentrant {
        require(msg.value >= 10**14, "Your bet must be greater");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created game, wait or cancel it");
        gamesP2P.push(Game( zeroAddress, msg.value, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[zeroAddress] = balanceP2PbyToken[zeroAddress].add(msg.value);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    // Создаем открыю игру P2P на пользовательском токене
    function createGameP2PbyToken(address _token, uint256 _amount, uint256 _hashBit) public payable nonReentrant {
        require(_amount >= 0, "Your bet must be greater");
        (bool gameIsReady,) = getOpenGameByCreator(msg.sender);
        require(!gameIsReady, "You have already created game, wait or cancel it");
        require(pay(msg.sender, address(this), _token, _amount), "Not enough tokens for game");
        gamesP2P.push(Game( _token, _amount, msg.sender, zeroAddress, zeroAddress, _hashBit, 0, (block.timestamp).add(blocksToGameOver) ));
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(_amount);
        emit GameP2PisOpen(msg.sender, zeroAddress);
    }

    // Играем в ранее созданную первую в списке открытую игру на BNB
    function playFirstOpenGameP2PbyBNB(uint8 _choice) public payable nonReentrant {
        playFirstOpenGameP2P(_choice, zeroAddress);
    }

    // Играем в ранее созданную первую в списке открытую игру с пользовательским токеном или BNB    
    function playFirstOpenGameP2P(uint8 _choice, address _token) public payable nonReentrant checkChoice(_choice) {
        (bool _gameIsReady, uint256 _index) = getFirstOpenGameByToken(_token);
        require(_gameIsReady, "Game is not found");
        _playOpenGame(_choice, _index);
    }

    // Играем в ранее созданную первую в списке открытую игру выбранного пользователя  
    function playFirstOpenGameByCreator(uint8 _choice, address _creator) public payable nonReentrant checkChoice(_choice) {
        (bool _gameIsReady, uint256 _index) = getOpenGameByCreator(_creator);
        require(_gameIsReady, "Game is not found");
        _playOpenGame(_choice, _index);
    }

    // Играем в ранее созданную открытую игру с указанием на её индекс
    function playOpenGameByIndex(uint8 _choice, uint256 _index) public payable nonReentrant checkChoice(_choice) {   
        require(gamesP2P[_index].player_2 != zeroAddress 
             && gamesP2P[_index].player_2 == zeroAddress 
             && gamesP2P[_index].timeGameOver < block.timestamp , "Game is not found");
            _playOpenGame(_choice, _index);
    }

    // Общая функция для игры по индеску
    function _playOpenGame(uint8 _choice, uint256 _index) internal {
        address _token = gamesP2P[_index].token;
        uint256 _balance= gamesP2P[_index].balance;
        require(pay(msg.sender, address(this), _token, _balance), "Not enough tokens for game");
        balanceP2PbyToken[_token] = balanceP2PbyToken[_token].add(_balance);
        gamesP2P[_index].player_2 = msg.sender;
        gamesP2P[_index].choice_2 = _choice;
        gamesP2P[_index].timeGameOver = (block.timestamp).add(blocksToGameOver);
        emit GameP2PisPlayed(gamesP2P[_index].player_1, msg.sender);
    }

    // Получаем индекс сыгранной но не закрытой игры по пользователю
    function getPlayedGame(address player) public view returns(bool, uint256) {
        for (uint256 i = 0; i < gamesP2P.length; i++) {
            if ((gamesP2P[i].player_1 == player || gamesP2P[i].player_2 == player) && gamesP2P[i].player_2 != zeroAddress && gamesP2P[i].winner == zeroAddress) {
                return (gamesP2P[i].player_1 == player, i);
            }
        }
        revert("You are not player or game is not found");
    }

    // Закрываем игру и производим выплату
    function closeGameAndGetMoney(uint8 _choice, uint256 secret) public nonReentrant checkChoice(_choice) {
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

    // Отменяем несыгранную игру
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

    // === Only for SuperUser === start
    
    function setNewOptionsForVRF(
        uint16 _requestConfirmations, 
        uint32 _callbackGasLimit,
        uint32 _numWords,
        uint64 _s_subscriptionId
        ) public onlyOwner {
            require(_requestConfirmations > 0, "Bad requestConfirmations");
            require(_callbackGasLimit > 0, "Bad callbackGasLimit");
            require(_numWords > 0, "Bad numWords");
            require(_s_subscriptionId > 0, "Bad s_subscriptionId");
            requestConfirmations = _requestConfirmations;
            callbackGasLimit = _callbackGasLimit;
            numWords = _numWords;
            s_subscriptionId = _s_subscriptionId;
    }

    function setFee(uint256 _fee) public onlyOwner {
        emit FeeChanged (FEEbyBet, _fee, msg.sender);
        FEEbyBet = _fee;
    }

    function setNftContractForFreeFee(address _address) public onlyOwner {
        emit NftContractChanged(nftContractForFreeFee, _address, msg.sender);
        nftContractForFreeFee = _address;
    }

    function setBlocksToGameOver(uint256 blocks) public onlyOwner {
        blocksToGameOver = blocks;
    }

    function transferOwner (address newAddress) public onlyOwner {
        require(!isContract(newAddress), "Contract cannot be the SuperUser");
        emit TransferedOwnership(msg.sender, newAddress);
    }

    function withdraw() public onlyOwner {
        require(address(this).balance > balanceP2PbyToken[zeroAddress], "Balance is too small for withdrawal");
        uint256 amountToWithdraw = (address(this).balance).sub(balanceP2PbyToken[zeroAddress]);
        pay(address(this), msg.sender, zeroAddress, amountToWithdraw);
    }

    function withdrawTokens(address _token) public onlyOwner nonReentrant {
        IERC20Metadata token = IERC20Metadata(_token);
        require(token.balanceOf(address(this)) > balanceP2PbyToken[_token], "Balance is too small for withdrawal");
        uint256 amountToWithdraw = (token.balanceOf(address(this)).sub(balanceP2PbyToken[_token]));
        pay(address(this), msg.sender, _token, amountToWithdraw);
    }
    // === Only for SuperUser === end

    // === Helpers === start
    function maxBetP2CbyBNB() public view returns(uint256) {
        return address(this).balance.sub(balanceP2PbyToken[zeroAddress]);
    }

    function maxBetP2CbyToken(address _token) public view returns(uint256) {
        IERC20Metadata token = IERC20Metadata(_token);
        return token.balanceOf(address(this)).sub(balanceP2PbyToken[_token]);
    }

    function pay(address _from, address _to, address _token, uint256 _amount) private returns(bool) {
        if (_token == zeroAddress && _from == address(this)){
            (bool success, ) = _to.call{value: _amount}("");
            return success;
        } else {
            IERC20Metadata token = IERC20Metadata(_token);
            bool success = token.transferFrom(_from, _to, _amount);
            return success;
        }
    }

    function calculateFee(uint256 amount) public view returns (uint256) {
        return IERC721(nftContractForFreeFee).balanceOf(msg.sender) > 0 ? 0 : amount.mul(FEEbyBet).div(1000000);
    }
    
    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
    // === Helpers === end

    receive() external payable {

    }
}