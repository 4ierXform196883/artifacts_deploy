#!/bin/bash

# Функция для получения значения из определенной строки и позиции в файле
# если при разделении табуляцией первый элемен совпадает с key
# возвращается значение на позиции pos (сам key имеет индекс 1)
get_file_value() {
  local file=$1
  local key=$2
  local pos=$3

  awk -v key="$key" -v pos="$pos" 'BEGIN {FS="\t"} $1 == key {print $pos}' "$file"
}

# Функция для изменения значения в определенной строке и позиции в файле
edit_file_value() {
  local file=$1
  local key=$2
  local pos=$3
  local replacement=$4

  awk -v key="$key" -v pos="$pos" -v replacement="$replacement" 'BEGIN {FS=OFS="\t"} $1 == key {$pos = replacement} 1' "$file" >temp.txt && mv temp.txt "$file"
}

# Функция для проверки ввода
verified_read() {
  local message=$1
  local regex=$2
  local default_value=$3
  local input

  while true; do
    read -p "$message" -r input

    # Если введено пустое значение и есть значение по умолчанию
    # то присвоить значение по умолчанию
    if [[ -z $input && -n $default_value ]]; then
      input=$default_value
    fi

    if [[ $input =~ $regex ]]; then
      break
    else
      echo "Invalid input" >&2
    fi
  done
  echo "$input"
}

# Принимает строку диапазона и возвращает массив чисел в этом диапазоне
# expand_range("1-3") => 1 2 3
expand_range() {
  local range="$1"                             # 6-9
  local start=$(echo "$range" | cut -d'-' -f1) # 6
  local end=$(echo "$range" | cut -d'-' -f2)   # 9
  seq "$start" "${end:-$start}"                # 6 7 8 9
}

# Принимает строку из диапазонов и запятых и возвращает массив чисел
# parse_range("1-3,5,7-9") => 1 2 3 5 7 8 9
parse_range() {
  local input="$1"
  local result=()

  # Разделить строку по запятым в массив
  IFS=',' read -ra ranges <<<"$input" # 1-3 5 7-9

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

# Функция для получения ключей (первых элементов) из файла
get_file_keys() {
  local file=$1
  local -a values
  local line

  # читаем файл построчно
  # разделяем по табуляции и берем первый элемент
  # '_' - placeholder переменная для оставшихся элементов строки
  while IFS=$'\t' read -r line _; do
    values+=("$line")
  done <"$file"

  echo "${values[@]}"
}

# Красивый вывод массива
# Ищет максимальную длину элемента массива
# вычисляет сколько элементов помещается в строку
# и выводит всё выровненно
print_array_indexed() {
  local -n arr=$1
  local count=0
  local indexed=()
  local maxLen=0

  # добавляем индекс к каждому элементу
  # vaule -> index) value
  for index in "${!arr[@]}"; do
    indexedItem="$((index + 1))) ${arr[index]}"
    indexed+=("$indexedItem")
    ((${#indexedItem} > maxLen)) && maxLen=${#indexedItem}
  done

  # вычисляем сколько элементов помещается в строку
  local terminal_width=$(tput cols)
  local items_per_line=$((terminal_width / (maxLen + 1)))

  # вывод элементов массива
  for i in "${indexed[@]}"; do
    printf "%-${maxLen}s " "$i"
    ((count++))
    if ((count % items_per_line == 0)); then
      echo
    fi
  done

  # вывод новой строки, если последняя строка содержит меньше элементов, чем items_per_line
  if ((count % items_per_line != 0)); then
    echo
  fi
}

# вывод файла в виде таблицы
print_table() {
  # первый аргумент - имя файла
  local file=$1
  if [ ! -f $file ]; then
    echo "File $file does not exist"
    return 1
  fi
  shift
  # остальные - заголовки столбцов
  local colNames=("$@")
  # data - массив массивов, каждый массив - столбец
  local -a data

  # Итериремся по файлу разделяя строки по табуляции
  while IFS=$'\t' read -r -a line; do
    # Итерируемся по элементам строки, index - номер элемента
    for index in "${!line[@]}"; do
      
      # Если индекс больше длины массива, то добавляем новый столбец
      if ((index >= ${#data[@]})); then
        # Объявляем новый столбец
        declare "column$index"
        # добавляем его просто как строку в массив
        data+=("column$index")
        # а затем достаём его по ссылке (-n - name reference)
        declare -n column=${data[index]}
        # и первым элементом добавляем в него заголовок
        column+=("${colNames[index]}")
      fi

      # Добавляем сам элемент в столбец
      declare -n column=${data[index]}
      column+=("${line[index]}")
    done
  done <"$file"

  # Вычисляем максимальную длину элемента в каждом столбце
  local maxLengths=()
  for index in "${!data[@]}"; do
    local -n col=${data[index]}
    local maxLen=0
    for item in "${col[@]}"; do
      ((${#item} > maxLen)) && maxLen=${#item}
    done
    maxLengths+=("$maxLen")
  done
  # Определяем количество строк
  local -n firstColumn=${data[0]}
  local numRows=${#firstColumn[@]}

  # Выводим данные с выравниванием
  for ((i = 0; i < $numRows; i++)); do
    for j in "${!data[@]}"; do
      local -n col=${data[$j]}
      printf "%-*s\t" "${maxLengths[$j]}" "${col[$i]}"
    done
    printf "\n"
  done
}

api_fill_project_id() {
  eval "$1=0"

  echo "Getting projects..."
  declare -A project_map
  local page=1
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  
  # Получение списка проектов
  # sed используется для удаления вложенного json'a под ключом "namespace" целиком
  # он не нужен и содежрит поле "id", что помешает парсингу в следующей строке
  local json=$(curl -s --request GET "$api_url/projects?simple=true&min_access_level=20&per_page=100&page=$page&access_token=$token" | sed 's/,"namespace":{[^}]*}//g')

  while [ "$json" != "[]" ]; do
    # Парсинг json'a для ключа "path"
    # awk -F '[:,]' := разделитель - двоеточие или запятая
    # for(i=1;i<=NF;i++) := перебор всех полей после разделения
    # if($i ~ /"path"/) := если поле содержит "path"
    # gsub(/[[:space:]]|"|/,"",$(i+1)) := удалить пробелы, кавычки и слеши из следующего поля
    # print $(i+1) := вывести следующее поле
    local new_project_paths=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"path"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
    # Парсинг json'a для ключа "id"
    local new_project_ids=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"id"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

    # Заполнение ассоциативного массива
    for i in "${!new_project_paths[@]}"; do
      project_map["${new_project_paths[i]}"]="${new_project_ids[i]}"
    done

    ((page++))
    json=$(curl -s --request GET "$api_url/projects?simple=true&min_access_level=20&per_page=100&page=$page&access_token=$token" | sed 's/,"namespace":{[^}]*}//g')
  done

  # Если не найдено проектов
  if [ ${#project_map[@]} -eq 0 ]; then
    return 1
  fi

  # Сортировка и вывод
  local sorted_paths=($(echo "${!project_map[@]}" | tr ' ' '\n' | sort))

  print_array_indexed sorted_paths

  local selected_index=$(verified_read "Select project: " "[0-9]+")
  eval "$1=${project_map[${sorted_paths[$((selected_index - 1))]}]}"
}


api_fill_branch_name() {
  local project_id=$1
  eval "$2=''"

  echo "Getting branches..."
  local branches=()
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  local json=$(curl -s --request GET "$api_url/projects/$project_id/repository/branches?per_page=100&access_token=$token")
  branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

  # Если не найдено ветвей
  if [ ${#branches[@]} -eq 0 ]; then
    return 1
  fi

  print_array_indexed branches

  local selected_index=$(verified_read "Select branch: " "[0-9]+")
  eval "$2=${branches[$((selected_index - 1))]}"
}

api_fill_job_name() {
  local project_id=$1
  local branch_name=$2
  eval "$3=''"
  
  echo "Getting jobs..."
  local jobs=()
  local page=1
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  # Получение списка успешных работ
  local json=$(curl -s --request GET "$api_url/projects/$project_id/jobs/?scope[]=success&per_page=100&page=$page&access_token=$token" | sed 's/,"pipeline":{[^}]*}//g; s/,"runner":{[^}]*}//g; s/,"user":{[^}]*}//g')
  
  while [ "$json" != "[]" ]; do
    # Массив названий работ
    local new_jobs=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
    # Массив веток, которым принадлежат работы
    local new_job_branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"ref"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

    # Выделение только тех работ, которые принадлежат выбранной ветке
    for ((i = 0; i < ${#new_jobs[@]}; i++)); do
      # Проверка на соответствие ветки и наличие работы в массиве (дубликаты не нужны)
      if [[ ${new_job_branches[$i]} == $branch_name ]] && [[ ! " ${jobs[@]} " =~ " ${new_jobs[$i]} " ]]; then
        jobs+=(${new_jobs[$i]})
      fi
    done

    ((page++))
    json=$(curl -s --request GET "$api_url/projects/$project_id/jobs/?scope[]=success&per_page=100&page=$page&access_token=$token" | sed 's/,"pipeline":{[^}]*}//g; s/,"runner":{[^}]*}//g; s/,"user":{[^}]*}//g')
  done

  # Если job'ов не найдено
  if [ ${#jobs[@]} -eq 0 ]; then
    return 1
  fi

  print_array_indexed jobs

  local selected_index=$(verified_read "Select job: " "[0-9]+")
  eval "$3=${jobs[$((selected_index - 1))]}"
}


api_fill_job_name() {
  local project_id=$1
  local branch_name=$2
  eval "$3=''"

  echo "Getting jobs..."
  local jobs=()
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  # Получение списка успешных работ
  local json=$(curl -s --request GET "$api_url/projects/$project_id/jobs/?scope[]=success&access_token=$token" | sed 's/,"pipeline":{[^}]*}//g; s/,"runner":{[^}]*}//g; s/,"user":{[^}]*}//g')
  # Массив названий работ
  local all_jobs=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
  # Массив веток, которым принадлежат работы
  local job_branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"ref"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))

  # Выделение только тех работ, которые принадлежат выбранной ветке
  for ((i = 0; i < ${#all_jobs[@]}; i++)); do
    # Проверка на соответствие ветки и наличие работы в массиве (дубликаты не нужны)
    if [[ ${job_branches[$i]} == $branch_name ]] && [[ ! " ${jobs[@]} " =~ " ${all_jobs[$i]} " ]]; then
      jobs+=(${all_jobs[$i]})
    fi
  done

  # Если не найдено работ
  if [ ${#jobs[@]} -eq 0 ]; then
    return 1
  fi

  print_array_indexed jobs

  local selected_index=$(verified_read "Select job: " "[0-9]+")
  eval "$3=${jobs[$((selected_index - 1))]}"
}

############################################
# Функции взаимодействия с пользователем
############################################

user_api_modification() {
  if [[ ! -f "$config_path" ]]; then
    mkdir -p $(dirname $config_path)
    touch "$config_path"
    echo -e "api_url\t-" >>"$config_path"
    echo -e 'token\t-' >>"$config_path"
  fi
  # Используем verified_read для валидации ввода regex'ом
  while true; do
    local action=$(verified_read "Choose action (edit [u]rl / edit [t]oken / [p]rint / [q]uit): " "[u|t|p|q]")
    case $action in
    u | U)
      user_edit_api_url
      ;;
    t | T)
      user_edit_token
      ;;
    p | P)
      user_print_config
      ;;
    q | Q)
      break
      ;;
    esac
  done
}

user_edit_api_url() {
  local new_api_url=$(verified_read "Enter new API URL: " "^[^[:space:]]+$")
  local test=$(curl -sf --request GET "$new_api_url/projects?simple=true&min_access_level=20")
  if [[ $? -ne 0 || $test != "[]" ]]; then
    echo "API URL is invalid" >&2
  else 
    edit_file_value "$config_path" "api_url" 2 "$new_api_url"
    echo "API URL changed successfully"
  fi
}

user_edit_token() {
  local new_token=$(verified_read "Enter new token: " "^[^[:space:]]+$")
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local test=$(curl -sf --request GET "$api_url/projects?simple=true&min_access_level=20&access_token=$new_token")
  if [[ ! $(curl -sf --request GET "$api_url/projects?simple=true&min_access_level=20&access_token=$new_token") || $test == "[]" ]]; then
    echo "Token is invalid" >&2
  else
    edit_file_value "$config_path" "token" 2 "$new_token"
    echo "Token changed successfully"
  fi
}

user_print_config() {
  local headers=("Key" "Value")
  print_table "$config_path" "${headers[@]}"
}


user_hosts_modification() {
  if [[ ! -f "$hosts_path" ]]; then
    mkdir -p $(dirname $hosts_path)
    touch "$hosts_path"
  fi
  while true; do
    local action=$(verified_read "Choose action ([a]dd / [e]dit / [d]elete / [p]rint / [q]uit): " "[a|e|d|p|q]")
    case $action in
    a | A)
      user_add_host
      ;;
    e | E)
      user_edit_host
      ;;
    d | D)
      user_delete_host
      ;;
    p | P)
      user_print_hosts
      ;;
    q | Q)
      break
      ;;
    esac
  done
}

user_add_host() {
  local name=$(verified_read "Name: " "^[^[:space:]]+$")
  local ip=$(verified_read "IP: " "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.?){4}$")
  local port=$(verified_read "Port [22]: " "^[0-9]+$" 22)
  local username=$(verified_read "Username: " "^[^[:space:]]+$")
  local password=$(verified_read "Password [-]: " "^[^[:space:]]+$" "-")
  echo -e "$name\t$ip\t$port\t$username\t$password" >>"$hosts_path"
}

user_edit_host() {
  local machine_names=($(get_file_keys "$hosts_path"))
  print_array_indexed machine_names

  local selected_index=$(verified_read "Select machine to edit: " "[0-9]+")
  local options=("[1] Name" "[2] IP" "[3] Port" "[4] Username" "[5] Password")
  local selected_option=$(verified_read "Select option (${options[*]}): " "[1-5]")
  local selected_machine=${machine_names[$((selected_index - 1))]}

  if [[ $selected_option -eq 5 ]]; then
    local new_password=$(verified_read "New password [-]: " "^[^[:space:]]+$" "-")
    edit_file_value "$hosts_path" "$selected_machine" 5 "$new_password"
  elif [[ $selected_option -eq 1 ]]; then
    local new_name=$(verified_read "New name: " "^[^[:space:]]+$")
    edit_file_value "$hosts_path" "$selected_machine" 1 "$new_name"
  elif [[ $selected_option -eq 2 ]]; then
    local new_ip=$(verified_read "New IP: " "^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])\.?){4}$")
    edit_file_value "$hosts_path" "$selected_machine" 2 "$new_ip"
  elif [[ $selected_option -eq 3 ]]; then
    local new_port=$(verified_read "New port [22]: " "^[0-9]+$" 22)
    edit_file_value "$hosts_path" "$selected_machine" 3 "$new_port"
  elif [[ $selected_option -eq 4 ]]; then
    local new_username=$(verified_read "New username: " "^[^[:space:]]+$")
    edit_file_value "$hosts_path" "$selected_machine" 4 "$new_username"
  fi
}

user_delete_host() {
  local machine_names=($(get_file_keys "$hosts_path"))
  print_array_indexed machine_names
  local user_input=$(verified_read "Enter lines to delete (1-2,3,99-101): " "^([0-9]+(-[0-9]+)?,)*([0-9]+(-[0-9]+)?)$")
  local parsed_array=($(parse_range "$user_input"))
  remove_lines "$hosts_path" "${parsed_array[@]}"
}

user_print_hosts() {
  local headers=("Name" "IP" "Port" "Username" "Password")
  print_table "$hosts_path" "${headers[@]}"
}

user_artifacts_modification() {
  if [[ ! -f "$artifacts_path" ]]; then
    mkdir -p $(dirname $artifacts_path)
    touch "$artifacts_path"
  fi
  while true; do
    local action=$(verified_read "Choose action ([a]dd / [e]dit / [c]opy / [d]elete / [p]rint / [q]uit): " "[a|e|c|d|p|q]")
    case $action in
    a | A)
      user_add_artifact
      ;;
    e | E)
      user_edit_artifact
      ;;
    c | C)
      user_copy_artifact
      ;;
    d | D)
      user_delete_artifact
      ;;
    p | P)
      user_print_artifacts
      ;;
    q | Q)
      break
      ;;
    esac
  done
}

user_add_artifact() {
  local project_id
  api_fill_project_id project_id
  if [ $project_id -eq 0 ]; then
    echo "No projects found" >&2
    return 1
  fi

  local branch_name
  api_fill_branch_name $project_id branch_name
  if [ -z $branch_name ]; then
    echo "No branches found" >&2
    return 1
  fi
  local job_name
  api_fill_job_name $project_id $branch_name job_name
  if [ -z $job_name ]; then
    echo "No jobs found" >&2
    return 1
  fi

  local files=$(verified_read "Files (separated by ';') [-]: " "^[^[:space:]]+$" "-")

  local name=$(verified_read "Name: " "^[^[:space:]]+$")

  data="$name\t$project_id\t$branch_name\t$job_name\t$files"
  echo -e "$data" >>"$artifacts_path"
}

user_edit_artifact() {
  local artifact_names=($(get_file_keys "$artifacts_path"))
  print_array_indexed artifact_names

  local selected_index=$(verified_read "Select artifact to edit: " "[0-9]+")
  local selected_artifact=${artifact_names[$((selected_index - 1))]}
  local options=("[1] Name" "[2] Project ID" "[3] Branch" "[4] Job" "[5] Files")
  local selected_option=$(verified_read "Select option (${options[*]}): " "[1-5]")

  case $selected_option in
  1)
    local new_name=$(verified_read "New name: " "^[^[:space:]]+$")
    edit_file_value "$artifacts_path" "$selected_artifact" 1 "$new_name"
    ;;
  2)
    local project_id branch_name job_name
    api_fill_project_id project_id
    if [ $project_id -eq 0 ]; then
      echo "No projects found" >&2
      return
    fi
    api_fill_branch_name $project_id branch_name
    if [ -z $branch_name ]; then
      echo "No branches found" >&2
      return
    fi
    api_fill_job_name $project_id $branch_name job_name
    if [ -z $job_name ]; then
      echo "No jobs found" >&2
      return
    fi
    edit_file_value "$artifacts_path" "$selected_artifact" 2 "$project_id"
    edit_file_value "$artifacts_path" "$selected_artifact" 3 "$branch_name"
    edit_file_value "$artifacts_path" "$selected_artifact" 4 "$job_name"
    ;;
  3)
    local project_id=$(get_file_value "$artifacts_path" "$selected_artifact" 2)
    local branch_name job_name
    api_fill_branch_name $project_id branch_name
    if [ -z $branch_name ]; then
      echo "No branches found" >&2
      return
    fi
    api_fill_job_name $project_id $branch_name job_name
    if [ -z $job_name ]; then
      echo "No jobs found" >&2
      return
    fi
    edit_file_value "$artifacts_path" "$selected_artifact" 3 "$branch_name"
    edit_file_value "$artifacts_path" "$selected_artifact" 4 "$job_name"
    ;;
  4)
    local project_id=$(get_file_value "$artifacts_path" "$selected_artifact" 2)
    local branch_name=$(get_file_value "$artifacts_path" "$selected_artifact" 3)
    local job_name
    api_fill_job_name $project_id $branch_name job_name
    if [ -z $job_name ]; then
      echo "No jobs found" >&2
      return
    fi
    edit_file_value "$artifacts_path" "$selected_artifact" 4 "$job_name"
    ;;
  5)
    local new_files=$(verified_read "New files (separated by ';') [-]: " "^[^[:space:]]+$" "-")
    edit_file_value "$artifacts_path" "$selected_artifact" 5 "$new_files"
    ;;
  esac
}

user_copy_artifact() {
  local artifact_names=($(get_file_keys "$artifacts_path"))
  print_array_indexed artifact_names

  local selected_index=$(verified_read "Select artifact to copy: " "[0-9]+")
  local selected_artifact=${artifact_names[$((selected_index - 1))]}
  local new_name=$(verified_read "New name: " "^[^[:space:]]+$")
  local old_project_id=$(get_file_value "$artifacts_path" "$selected_artifact" 2)
  local old_branch_name=$(get_file_value "$artifacts_path" "$selected_artifact" 3)
  local old_job_name=$(get_file_value "$artifacts_path" "$selected_artifact" 4)
  local old_files=$(get_file_value "$artifacts_path" "$selected_artifact" 5)

  data="$new_name\t$old_project_id\t$old_branch_name\t$old_job_name\t$old_files"
  echo -e "$data" >>"$artifacts_path"
}

user_delete_artifact() {
  local artifact_names=($(get_file_keys "$artifacts_path"))
  print_array_indexed artifact_names
  local user_input=$(verified_read "Enter lines to delete (1-2,3,99-101): " "^([0-9]+(-[0-9]+)?,)*([0-9]+(-[0-9]+)?)$")
  local parsed_array=($(parse_range "$user_input"))
  remove_lines "$artifacts_path" "${parsed_array[@]}"
}

user_print_artifacts() {
  local headers=("Name" "Project ID" "Branch" "Job" "Files")
  print_table "$artifacts_path" "${headers[@]}"
}

user_scenario_modification() {
  if [[ -z "$scenario_path" ]]; then
    echo "Scenario path is not specified" >&2
    echo "Please re-run the script with -s <scenario_path>" >&2
    verified_read "Press enyer to continue" ""
    return 1
  fi
  if [[ ! -f "$scenario_path" ]]; then
    mkdir -p $(dirname $scenario_path)
    touch "$scenario_path"
  fi
  while true; do
    local action=$(verified_read "Choose action ([a]dd / [e]dit / [d]elete / [p]rint / [q]uit): " "[a|e|d|p|q]")
    case $action in
    a | A)
      user_add_scenario_pair
      ;;
    d | D)
      user_delete_scenario_pair
      ;;
    e | E)
      user_edit_scenario_pair
      ;;
    p | P)
      user_print_scenario_info
      ;;
    q | Q)
      break
      ;;
    esac
  done
}

user_add_scenario_pair() {
  local artifact_names=($(get_file_keys "$artifacts_path"))
  print_array_indexed artifact_names

  local selected_index=$(verified_read "Select artifact: " "[0-9]+")
  local selected_artifact=${artifact_names[$((selected_index - 1))]}
  local machine_names=($(get_file_keys "$hosts_path"))
  machine_names+=("Local")
  print_array_indexed machine_names

  local selected_index=$(verified_read "Select machine: " "[0-9]+")
  local selected_machine=${machine_names[$((selected_index - 1))]}
  local machine_path=$(verified_read "Enter path on machine: " "^[^[:space:]]+$")

  data="$selected_artifact\t$selected_machine\t$machine_path"
  echo -e "$data" >>"$scenario_path"
}

user_edit_scenario_pair() {
  local scenario_pairs=($(get_file_keys "$scenario_path"))
  print_array_indexed scenario_pairs

  local selected_index=$(verified_read "Select scenario to edit: " "[0-9]+")
  local options=("[1] Artifact" "[2] Machine" "[3] Path")
  local selected_option=$(verified_read "Select option (${options[*]}): " "[1-3]")
  local selected_scenario=${scenario_pairs[$((selected_index - 1))]}

  case $selected_option in
  1)
    local artifact_names=($(get_file_keys "$artifacts_path"))
    print_array_indexed artifact_names
    local selected_index=$(verified_read "Select artifact: " "[0-9]+")
    local selected_artifact=${artifact_names[$((selected_index - 1))]}
    edit_file_value "$scenario_path" "$selected_scenario" 1 "$selected_artifact"
    ;;
  2)
    local machine_names=($(get_file_keys "$hosts_path"))
    machine_names+=("Local")
    print_array_indexed machine_names
    local selected_index=$(verified_read "Select machine: " "[0-9]+")
    local selected_machine=${machine_names[$((selected_index - 1))]}
    edit_file_value "$scenario_path" "$selected_scenario" 2 "$selected_machine"
    ;;
  3)
    local new_path=$(verified_read "New path on machine: " "^[^[:space:]]+$")
    edit_file_value "$scenario_path" "$selected_scenario" 3 "$new_path"
    ;;
  esac
}

user_delete_scenario_pair() {
  local scenario_pairs=($(get_file_keys "$scenario_path"))
  print_array_indexed scenario_pairs
  local user_input=$(verified_read "Enter lines to delete (1-2,3,99-101): " "^([0-9]+(-[0-9]+)?,)*([0-9]+(-[0-9]+)?)$")
  local parsed_array=($(parse_range "$user_input"))
  remove_lines "$scenario_path" "${parsed_array[@]}"
}

user_print_scenario_info() {
  local headers=("Artifact" "Machine" "Path")
  print_table "$scenario_path" "${headers[@]}"
}

user_display_menu() {
  echo ""
  echo "---- Artifacts Deploy ----"
  echo "1) Configure API"
  echo "2) Hosts modification"
  echo "3) Artifacts modification"
  echo "4) Scenario modification"
  echo "q) Quit"
  echo "--------------------------"
  echo ""
}

main_edit() {
  while true; do
    user_display_menu
    read -p "Enter option: " -r option
    case $option in
    1)
      user_api_modification
      ;;
    2)
      user_hosts_modification
      ;;
    3)
      user_artifacts_modification
      ;;
    4)
      user_scenario_modification
      ;;
    q | Q)
      exit 0
      ;;
    *)
      echo "Invalid option" >&2
      ;;
    esac
  done
}

main_deploy() {
  if [[ ! -f "$scenario_path" ]]; then
    echo "Scenario path is not specified" >&2
    echo "Please re-run the script with -s <scenario_path>" >&2
    exit 1
  fi
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  # Итерируемся по строкам файла сценария, разделяем по табуляции
  while IFS=$'\t' read -r -a line; do
    # достаём имя артефакта и затем его данные
    local artifact_name=${line[0]}
    local artifact_project_id=$(get_file_value "$artifacts_path" "$artifact_name" 2)
    local artifact_branch_name=$(get_file_value "$artifacts_path" "$artifact_name" 3)
    local artifact_job_name=$(get_file_value "$artifacts_path" "$artifact_name" 4)
    # строку с файлами сразу разбиваем на массив
    local artifact_files=($(get_file_value "$artifacts_path" "$artifact_name" 5 | tr ';' '\n'))
    # достаём данные о машине (только если не Local)
    local machine_name=${line[1]}
    if [[ $machine_name != "Local" ]]; then
      local machine_ip=$(get_file_value "$hosts_path" "$machine_name" 2)
      local machine_port=$(get_file_value "$hosts_path" "$machine_name" 3)
      local machine_username=$(get_file_value "$hosts_path" "$machine_name" 4)
      local machine_password=$(get_file_value "$hosts_path" "$machine_name" 5)
    fi
    local machine_path=${line[2]}
    # Скачиваем артефакты
    rm -rf $cache_path/$artifact_name
    mkdir -p $cache_path/$artifact_name
    cd $cache_path/$artifact_name
    # Если не указаны файлы, то скачиваем архив целиком
    if [ "${artifact_files[0]}" == "-" ]; then
      echo "Downloading artifacts for $artifact_name"
      curl --location --output "artifacts.zip" --request GET "$api_url/projects/$artifact_project_id/jobs/artifacts/$artifact_branch_name/download?job=$artifact_job_name&access_token=$token"
      unzip artifacts.zip
      rm artifacts.zip
    # Иначе скачиваем только указанные файлы
    else
      echo "Downloading ${#artifact_files[@]} artifact files for $artifact_name"
      for file in "${artifact_files[@]}"; do
        echo "Downloading $file"
        mkdir -p $(dirname $file)
        curl --location --output "$file" --request GET "$api_url/projects/$artifact_project_id/jobs/artifacts/$artifact_branch_name/raw/$file?job=$artifact_job_name&access_token=$token"
      done
    fi
    # Непосредственно деплой
    echo "Deploying to $machine_name($machine_path)"
    # Путь на локальной машине считается относительно ДИРЕКТОРИИ ПОЛЬЗОВАТЕЛЯ
    # (ну чтобы не было различий с деплоем на удаленные машины)
    if [[ $machine_name == "Local" ]]; then
      if [[ $machine_path != /* ]]; then
        machine_path="$HOME/$machine_path"
      fi
      mkdir -p $machine_path
      cp -r $cache_path/$artifact_name/* $machine_path
    # Если пароль не указан, подразумеваем что есть беспрепятственный доступ по ключу
    # и используем scp
    elif [[ $machine_password == "-" ]]; then
      ssh -P $machine_port $machine_username@$machine_ip "mkdir -p $machine_path"
      scp -P $machine_port -r $cache_path/$artifact_name/* $machine_username@$machine_ip:$machine_path
    # Иначе используем sftp с sshpass
    else
      ssh -P $machine_port $machine_username@$machine_ip "mkdir -p $machine_path"
      SSHPASS=$machine_password sshpass -e sftp -P $machine_port -oBatchMode=no -b - "$machine_username@$machine_ip" <<EOF
lcd $cache_path/$artifact_name
cd $machine_path
put -r *
bye
EOF
    fi
  done <"$scenario_path"
  rm -rf $cache_path
}

artifacts_path="$HOME/.config/artifacts-deploy/.artifacts"
config_path="$HOME/.config/artifacts-deploy/.deployconfig"
hosts_path="$HOME/.config/artifacts-deploy/.hosts"
cache_path="$HOME/.config/artifacts-deploy/cache" # лучше не менять, так как используется rm -rf
scenario_path=""
edit_mode=true

# Парсинг аргументов командной строки
while [[ $# -gt 0 ]]; do
  case "$1" in
  # -a или --artifacts
  -a | --artifacts)
    artifacts_path="$2"
    shift 2
    ;;
  -h | --hosts)
    hosts_path="$2"
    shift 2
    ;;
  -c | --config)
    config_path="$2"
    shift 2
    ;;
  -s | --scenario)
    scenario_path="$2"
    shift 2
    ;;
  -p)
    edit_mode=false
    shift 1
    ;;
  *)
    echo "Invalid option: $1"
    exit 1
    ;;
  esac
done

if [ "$edit_mode" = true ]; then
  stty -echoctl
  trap 'main_edit' SIGINT 
  main_edit
else
  main_deploy
fi
