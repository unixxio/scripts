#!/bin/bash

#########################################################
#                                                       #
#  Description : Add MySQL/MariaDB user and/or database #
#  Author      : Unixx.io                               #
#  E-mail      : github@unixx.io                        #
#  GitHub      : https://www.github.com/unixxio         #
#  Last Update : December 30, 2021                      #
#                                                       #
#########################################################

function verify_permissions {
    if [[ ${EUID} -ne 0 ]]; then
       echo -e "\nThis script must be run as root.\n"
       exit 1
    fi
}

function install_packages {
    PACKAGES="openssl"

    echo -e "\nInstalling required packages for this script. Please wait..."
    echo -e "Packages : ${PACKAGES}"
    #echo -e "\nInstalling required packages (${PACKAGES}) for this script. Please wait..."
    apt-get update > /dev/null 2>&1 && apt-get upgrade -y > /dev/null 2>&1
    apt-get install ${PACKAGES} -y > /dev/null 2>&1
}

function verify_db_connection {
    DEFAULTS_FILE="/root/.my.cnf"
    SQL_ROOT_PASSWORD="$(cat ${DEFAULTS_FILE} | grep password | awk {'print $3'})"

    while ! mysql -u root -p${SQL_ROOT_PASSWORD} -e ";" > /dev/null 2>&1 ; do
        echo -e "\nThe root password for MySQL/MariaDB is incorrect. Please enter the correct password."
        echo -e -n "Password : "
        read SQL_ROOT_PASSWORD
    done

    CREDENTIALS=(
        "[client]"
        "user = root"
        "password = ${SQL_ROOT_PASSWORD}"
    )
    printf '%s\n' "${CREDENTIALS[@]}" > ${DEFAULTS_FILE}
}

function create_credentials {
    function create_database_user {
        echo -e "\nPlease enter the username you want to create."
        echo -e -n "Username : "
        read USERNAME

       if [ -z ${USERNAME} ]; then
           echo -e "\n[ Warning ] The username cannot be empty!"
           create_database_user
       fi

        RESULT="$(mysql -se "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '${USERNAME}')")"
        if [ "${RESULT}" == 1 ]; then
            PS="[ Warning ] The user ${USERNAME} already exists. Do you want to create a new database for this user? [Y/n] "
            PS3="$(echo -e "\n${PS}")"
            read -r -p "${PS3} " RESPONSE
            case "${RESPONSE}" in
                [yY][eE][sS]|[yY])
                    create_database_name_existing_user
                    ;;
                [nN][oO]|[Nn])
                    PS="Do you want to grant ${USERNAME} permissions to an existing database? [Y/n] "
                    PS3="$(echo -e "\n${PS}")"
                    read -r -p "${PS3} " RESPONSE
                    case "${RESPONSE}" in
                        [yY][eE][sS]|[yY])
                            select_existing_database
                            ;;
                        [nN][oO]|[Nn])
                            create_database_user
                            ;;
                        *)
                            # Default option if none selected
                            select_existing_database
                            ;;
                    esac
                    ;;
                *)
                    # Default option if none selected
                    create_database_name_existing_user
                    ;;
            esac
        else
            create_database_name
        fi
    }

    function select_existing_database {
        LIST_DATABASES="$(mysql --skip-column-names -e "SHOW DATABASES;" | grep -vw "information_schema" | grep -vw "performance_schema" | grep -vw "mysql")"

        echo -e "\nList of all databases :\n"
        PS="Select a database (number) : "
        PS3="$(echo -e "\n${PS}")"
        OPTIONS=(${LIST_DATABASES})
        select DBNAME in "${OPTIONS[@]}";
        do

            echo -e "\nYou have selected database : ${DBNAME}"

            PS="Is this correct? [y/N] "
            PS3="$(echo -e "\n${PS}")"
            read -r -p "${PS3} " RESPONSE
            case "${RESPONSE}" in
                [yY][eE][sS]|[yY])
                    grant_permissions_existing_database
                    ;;
                [nN][oO]|[Nn])
                    select_existing_database
                    ;;
                *)
                    # Default option if none selected
                    select_existing_database
                    ;;
            esac
            break; # this one must stay
        done
    }

    function create_database_name {
        echo -e "\nPlease enter the database name you want to create for user ${USERNAME}."
        echo -e -n "Database : "
        read DBNAME

       if [ -z ${DBNAME} ]; then
           echo -e "\n[ Warning ] The database name cannot be empty!"
           create_database_name
       fi

        RESULT="$(mysql --skip-column-names -e "SHOW DATABASES LIKE '${DBNAME}'")"
        if [ "${RESULT}" == "${DBNAME}" ]; then
            echo -e "\n[ Error ] The database ${DBNAME} already exists. Please create another database."
            create_database_name
        else
            create_database_password
        fi
    }

    function create_database_name_existing_user {
        echo -e "\nPlease enter the database name you want to create for user ${USERNAME}."
        echo -e -n "Database : "
        read DBNAME

       if [ -z ${DBNAME} ]; then
           echo -e "\n[ Warning ] The database name cannot be empty!"
           create_database_name_existing_user
       fi

        RESULT="$(mysql --skip-column-names -e "SHOW DATABASES LIKE '${DBNAME}'")"
        if [ "${RESULT}" == "${DBNAME}" ]; then
            echo -e "\n[ Error ] The database ${DBNAME} already exists. Please create another database."
            create_database_name_existing_user
        else

            echo -e "\nYou have entered : ${DBNAME}"

            PS="Is this correct? [Y/n] "
            PS3="$(echo -e "\n${PS}")"
            read -r -p "${PS3} " RESPONSE
            case "${RESPONSE}" in
                [yY][eE][sS]|[yY])
                    create_database_existing_user
                    exit 0
                    ;;
                [nN][oO]|[Nn])
                    create_database_name_existing_user
                    ;;
                *)
                    # Default option if none selected
                    create_database_existing_user
                    exit 0
                    ;;
            esac
        fi
    }

    function create_database_password {
        PS="Do you want to generate a random password for user ${USERNAME}? [Y/n] "
        PS3="$(echo -e "\n${PS}")"
        read -r -p "${PS3} " RESPONSE
        case "${RESPONSE}" in
            [yY][eE][sS]|[yY])
	        generate_password
                ;;
            [nN][oO]|[Nn])
    	        echo -e "\nPlease enter a password for ${USERNAME}."
    	        echo -e -n "Password : "
    	        read PASSWORD
                if [ -z ${PASSWORD} ]; then
                    echo -e "\n[ Warning ] The password cannot be empty!"
                    create_database_password
                fi
                ;;
            *)
                # Default option if none selected
                generate_password
                ;;
        esac

        echo -e "\nDatabase : ${DBNAME}"
        echo -e "Username : ${USERNAME}"
        echo -e "Password : ${PASSWORD}"

        PS="Do you want to continue? [Y/n] "
        PS3="$(echo -e "\n${PS}")"
        read -r -p "${PS3} " RESPONSE
        case "${RESPONSE}" in
            [yY][eE][sS]|[yY])
                create_database
                save_credentials
                exit 0
                ;;
            [nN][oO]|[Nn])
                clear
                create_credentials
                ;;
            *)
                # Default option if none selected
                create_database
                save_credentials
                exit 0
                ;;
        esac
    }

    function save_credentials {
        SAVEPATH="/root/.mysql"
        FILE=".my.${USERNAME}.cnf"
        mkdir -p ${SAVEPATH}
        CREDENTIALS=(
            "[client]"
            "user = ${USERNAME}"
            "password = ${PASSWORD}"
        )
        printf '%s\n' "${CREDENTIALS[@]}" > ${SAVEPATH}/${FILE}
        echo -e "The credentials have been saved to : ${SAVEPATH}/${FILE}\n"
    }

    create_database_user
}

function generate_password {
    PASSWORD="$(openssl rand -base64 30 | tr -d "=+/" | cut -c1-16)"
}

function create_database {
    mysql -e "CREATE DATABASE ${DBNAME} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    mysql -e "CREATE USER ${USERNAME}@localhost IDENTIFIED BY '${PASSWORD}';"
    mysql -e "CREATE USER ${USERNAME}@127.0.0.1 IDENTIFIED BY '${PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'127.0.0.1';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "\nThe database ${DBNAME} is successfully created and ${USERNAME} has been granted permissions."
}

function create_database_existing_user {
    mysql -e "CREATE DATABASE ${DBNAME} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'127.0.0.1';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "\nThe database ${DBNAME} is successfully created and ${USERNAME} has been granted permissions.\n"
}

function grant_permissions_existing_database {
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'localhost';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${USERNAME}'@'127.0.0.1';"
    mysql -e "FLUSH PRIVILEGES;"

    echo -e "\nThe user ${USERNAME} has been granted permissions on ${DBNAME} successfully.\n"
}

clear
verify_permissions
install_packages
verify_db_connection
create_credentials
exit 0
