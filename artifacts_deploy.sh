#!/bin/bash

artifacts_path="artifacts.txt"
locations_path="locations.txt"

# Принимает строку диапазона и возвращает массив чисел в этом диапазоне
# expand_range("1-3") => 1 2 3
expand_range() {
  local range="$1" # 6-9
  local start=$(echo "$range" | cut -d'-' -f1) # 6
  local end=$(echo "$range" | cut -d'-' -f2) # 9
  seq "$start" "${end:-$start}" # 6 7 8 9
}

# Принимает строку из диапазонов и запятых и возвращает массив чисел
# parse_range("1-3,5,7-9") => 1 2 3 5 7 8 9
parse_range() {
  local input="$1"
  local result=()

    # Разделить строку по запятым в массив
    IFS=',' read -ra ranges <<< "$input" # 1-3 5 7-9

    # Перебор каждого элемента в массиве
    for range in "${ranges[@]}"; do
      if [[ $range =~ "-" ]]; then
        # Обработка диапазона функцией expand_range
        expanded_range=$(expand_range "$range")
        result+=($expanded_range)
      else
        # Добавление одиночного числа в массив
        result+=("$range")
      fi
    done

    # Возвращение массива
    echo "${result[@]}"
  }

# Функция для удаления строк из файла
# Принимает имя файла и **массив** номеров строк для удаления
remove_lines() {
  local file="$1" # имя файла
  # массив номеров строк ($@ - все аргументы, ${@:2} - все аргументы начиная со второго)
  local lines=("${@:2}")
  # обратная сортировка чтобы удаление не нарушило порядок строк
  local lines=($(printf "%s\n" "${lines[@]}" | sort -rn))
  for line_number in "${lines[@]}"; do
    # используем утилиту манипуляции потоками (sed) для удаления строки
    # -i := edit in place, d := delete line
    sed -i "${line_number}d" "$file"
  done
}

# Функция для добавления SSH-директории
add_ssh_location() {
  read -p "IP: " ip
  read -p "Port (usually 22): " port
  read -p "Username: " username
  read -p "Password: " password
  read -p "Directory (or multiple, separated with ';'): " directory
  # Разделение директорий по точке с запятой
  # tr - translate, заменяет все ';' на '\n'
  local directories=($(echo $directory | tr ';' '\n'))
  read -p "Name: " name
  # Конкатенация данных в строку
  # #directories[@] - длина массива
  for ((i=0; i < ${#directories[@]}; i++)); do
    # Имя машины заменяется на "name(directory)"
    name_dir="${name}(${directories[i]})"
    data="$name_dir\t$ip\t$port\t$username\t$password\t${directories[i]}"
    # Добавление данных в файл
    echo -e "$data" >> "$locations_path"
  done
}


# Функция для добавления локальной директории
add_localhost_location() {
  read -p "Directory: " directory
  read -p "Name: " name
  # Разделение данных табами
  data="$name\tlocalhost\t-\t-\t-\t$directory"
  # Добавление данных в файл
  echo -e "$data" >> "$locations_path"
}

# Функция для удаления данных
# По сути просто user input + remove_lines
remove_data() {
  local file="$1"
  # -F'\t' := разделителем в строке является табуляция
  # NR := номер строки
  # $1 := первое поле строки (имя машины/артефакта)
  awk -F'\t' '{print NR ") " $1}' "$file"
  read -p "Enter lines to delete (1-2,3,99-101): " user_input
  parsed_array=($(parse_range "$user_input"))
  remove_lines "$file" "${parsed_array[@]}"
}

# Функция для отображения меню
display_menu() {
  echo ""
  echo "---- Artifacts Deploy ----"
  echo "1) Add ssh location"
  echo "2) Add localhost location"
  echo "3) Add artifacts"
  echo "4) Remove location"
  echo "5) Remove artifacts"
  echo "6) Print locations"
  echo "7) Print artifacts"
  echo "d) Deploy"
  echo "q) Quit"
  echo "--------------------------"
  echo ""
}

# Функция для добавления артефактов в файл
add_artifacts() {
  read -p "Api URL: " api_url
  read -p "Access token: " token
  # Получение списка проектов
  # sed используется для удаления вложенного json'a под ключом "namespace" целиком
  # он не нужен и содежрит поле "id", что помешает парсингу в следующей строке
  local json=$(curl -s --request GET "$api_url/projects?simple=true&min_access_level=20&per_page=100&access_token=$token" | sed 's/,"namespace":{[^}]*}//g')
  # Парсинг json'a для ключа "id"
  # awk -F '[:,]' := разделитель - двоеточие или запятая
  # for(i=1;i<=NF;i++) := перебор всех полей после разделения
  # if($i ~ /"id"/) := если поле содержит "id"
  # gsub(/[[:space:]]|"|/,"",$(i+1)) := удалить пробелы, кавычки и слеши из следующего поля
  # print $(i+1) := вывести следующее поле
  local values=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"id"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
  # Парсинг для ключа "path"
  local keys=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"path"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

  # Создание ассоциативного массива
  declare -A name_to_id
  # Перебор массива ключей
  for ((i=0; i < ${#keys[@]}; i++)); do
    # Наполнение ассоциативного массива парами ключ-значение
    name_to_id[${keys[$i]}]=${values[$i]}
  done

  read -p "Project name: " project_name
  local project_id=${name_to_id[$project_name]}

  # Получение списка веток
  local json=$(curl -s --request GET "$api_url/projects/$project_id/repository/branches?access_token=$token")
  local branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

  # Вывод пользователю списка веток
  for ((i=0; i < ${#branches[@]}; i++)); do
    echo "$((i+1))) ${branches[i]}"
  done

  read -p "Select branch (number): " branch_number
  local branch_name=${branches[$((branch_number-1))]}

  # Получение списка успешных работ
  local json=$(curl -s --request GET "$api_url/projects/$project_id/jobs/?scope[]=success&access_token=$token" | sed 's/,"pipeline":{[^}]*}//g; s/,"runner":{[^}]*}//g; s/,"user":{[^}]*}//g')
  # Массив названий работ
  local all_jobs=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
  # Массив веток, которым принадлежат работы
  local job_branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"ref"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
  local jobs=()

  # Выделение только тех работ, которые принадлежат выбранной ветке
  for ((i=0; i < ${#all_jobs[@]}; i++)); do
    # Проверка на соответствие ветки и наличие работы в массиве (дубликаты не нужны)
    if [[ ${job_branches[$i]} == $branch_name ]] && [[ ! " ${jobs[@]} " =~ " ${all_jobs[$i]} " ]]; then
      jobs+=(${all_jobs[$i]})
    fi
  done

  # Вывод пользователю списка работ
  for ((i=0; i < ${#jobs[@]}; i++)); do
    echo "$((i+1))) ${jobs[i]}"
  done

  read -p "Select job (number): " job_number
  local job_name=${jobs[$((job_number-1))]}

  # Сохранение имён всёх машин из файла
  local machine_names=($(awk -F'\t' '{print $1}' "$locations_path"))
  # Вывод пользователю списка машин
  for index in "${!machine_names[@]}"; do
    printf "%d) %s\n" $((index+1)) "${machine_names[index]}"
  done
  read -p "Select machines (1-2,3,99-101): " machines
  local machines=($(parse_range "$machines"))

  # Фильтрация машин по выбранным номерам
  local selected_machines=()
  for index in "${machines[@]}"; do
    selected_machines+=("${machine_names[index-1]}")
  done
  machine_names=("${selected_machines[@]}")

  IFS=','
  local machines="${machine_names[*]}"

  read -p "Name: " name
  # Конкатенация данных в строку
  data="$name\t$api_url\t$token\t$project_id\t$branch_name\t$job_name\t$machines"
  echo -e "$data" >> "$artifacts_path"
}

deploy() {
  # Чтение файла с артефактами
  while IFS=$'\t' read -r -a line; do
    local name=${line[0]}
    local api_url=${line[1]}
    local token=${line[2]}
    local project_id=${line[3]}
    local branch_name=${line[4]}
    local job_name=${line[5]}
    local machines=($(echo "${line[6]}" | tr ',' '\n'))
    local machines_content=() # Массив для хранения данных о машинах
    # Итерация по каждому первому слову
    for mname in "${machines[@]}"; do
        while IFS= read -r mline; do
            if [[ $mline == "$mname"* ]]; then
                machines_content+=("$mline")
            fi
        done < "$locations_path"
    done
    echo "Downloading artifacts for $name"
    curl --location --output "artifacts.zip" --request GET "$api_url/projects/$project_id/jobs/artifacts/$branch_name/download?job=$job_name&access_token=$token"
    unzip artifacts.zip -d artifacts
    # Итерация по каждой машине
    for machine in "${machines_content[@]}"; do
      local machine_data=($(echo "$machine" | tr '\t' '\n'))
      local name=${machine_data[0]}
      local ip=${machine_data[1]}
      local port=${machine_data[2]}
      local username=${machine_data[3]}
      local password=${machine_data[4]}
      local directory=${machine_data[5]}

      echo "Deploying to $name"

      
      if [[ $ip == "localhost" ]]; then
        cp -r artifacts/* $directory
        echo "success"
      else
        export SSHPASS=$password
        # использование sshpass для автоматического ввода пароля
        sshpass -e sftp -P $port -oBatchMode=no -b - "$username@$ip" << EOD
lcd artifacts
cd $directory
put -r *
bye
EOD
        echo "success"
      fi
    done
    rm -rf artifacts
    rm artifacts.zip
  done < "$artifacts_path"
}

# Функции для вывода данных по артефактам
print_artifacts() {
  while IFS= read -r line; do
      name=$(echo "$line" | awk -F'\t' '{print $1}')
      machines=$(echo "$line" | awk -F'\t' '{print $7}')
      machines=($(echo "$machines" | tr ',' '\n'))

      echo "Artifacts name: $name, machines: ${machines[@]}"
  done < "$artifacts_path"
}

# Функции для вывода данных по локациям
print_locations() {
  while IFS= read -r line; do
      name=$(echo "$line" | awk -F'\t' '{print $1}')
      ip=$(echo "$line" | awk -F'\t' '{print $2}')
      dir=$(echo "$line" | awk -F'\t' '{print $6}')

      echo "Location name: $name, IP: $ip, directory: $dir"
  done < "$locations_path"
}

main() {
  while true; do
    display_menu
    read -p "Enter your choice: " choice
    case $choice in
      1)
        add_ssh_location
        ;;
      2)
        add_localhost_location
        ;;
      3)
        add_artifacts
        ;;
      4)
        remove_data $locations_path
        ;;
      5)
        remove_data $artifacts_path
        ;;
      6)
        print_locations
        ;;
      7)
        print_artifacts
        ;;
      d|D)
        deploy
        ;;
      q|Q)
        exit 0
        ;;
      *)
        echo "Invalid choice"
        ;;
    esac
  done
}

# Парсинг аргументов командной строки
while [[ $# -gt 0 ]]; do
  case "$1" in
    # -a или --artifacts
    -a|--artifacts)
      artifacts_path="$2"
      echo "Artifacts path: $artifacts_path"
      shift 2
      ;;
    # -l или --locations
    -l|--locations)
      locations_path="$2"
      echo "Locations path: $locations_path"
      shift 2
      ;;
    *)
      echo "Invalid option: $1"
      exit 1
      ;;
  esac
done

main
