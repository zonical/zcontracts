SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `zcontracts`
--

-- --------------------------------------------------------

--
-- Table structure for table `contract_progress`
--

CREATE TABLE `contract_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `progress` int(11) NOT NULL DEFAULT '0',
  `complete` bit(1) NOT NULL DEFAULT b'0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `objective_progress`
--

CREATE TABLE `objective_progress` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}',
  `objective_id` int(11) DEFAULT NULL,
  `progress` int(11) DEFAULT '0',
  `fires` int(11) DEFAULT '0',
  `complete` bit(1) NOT NULL DEFAULT b'0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `selected_contract`
--

CREATE TABLE `selected_contract` (
  `steamid64` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contract_uuid` char(64) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '{}'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `contract_progress`
--
ALTER TABLE `contract_progress`
  ADD UNIQUE KEY `contract_key` (`steamid64`,`contract_uuid`);

--
-- Indexes for table `objective_progress`
--
ALTER TABLE `objective_progress`
  ADD UNIQUE KEY `objective_key` (`steamid64`,`contract_uuid`,`objective_id`);

--
-- Indexes for table `selected_contract`
--
ALTER TABLE `selected_contract`
  ADD UNIQUE KEY `steamid64` (`steamid64`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
