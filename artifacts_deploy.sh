#!/bin/bash

# Функция для получения значения из определенной строки и позиции в файле
# если при разделении табуляцией первый элемен совпадает с key
# возвращается значение на позиции pos (сам key имеет индекс 1)
get_file_value() {
  local filename=$1
  local key=$2
  local pos=$3

  awk -v key="$key" -v pos="$pos" 'BEGIN {FS="\t"} $1 == key {print $pos}' "$filename"
}

# Функция для изменения значения в определенной строке и позиции в файле
edit_file_value() {
  local filename=$1
  local key=$2
  local pos=$3
  local replacement=$4

  awk -v key="$key" -v pos="$pos" -v replacement="$replacement" 'BEGIN {FS=OFS="\t"} $1 == key {$pos = replacement} 1' "$filename" >temp.txt && mv temp.txt "$filename"
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
  local filename=$1
  local -a values
  local line

  # читаем файл построчно
  # разделяем по табуляции и берем первый элемент
  # '_' - placeholder переменная для оставшихся элементов строки
  while IFS=$'\t' read -r line _; do
    values+=("$line")
  done <"$filename"

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
  # value -> (index) value
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
  shift
  # остальные - заголовки столбцов
  local colNames=("$@")
  # data - массив массивов, каждый массив - столбец
  local -a data

  # Итерируемся по файлу разделяя строки по табуляции
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
  local project_ids=()
  local project_paths=()
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

    project_ids=("${project_ids[@]}" "${new_project_ids[@]}")
    project_paths=("${project_paths[@]}" "${new_project_paths[@]}")

    ((page++))
    json=$(curl -s --request GET "$api_url/projects?simple=true&min_access_level=20&per_page=100&page=$page&access_token=$token" | sed 's/,"namespace":{[^}]*}//g')
  done
  if [ ${#project_ids[@]} -eq 0 ]; then
    echo "No projects found" >&2
    return
  fi

  print_array_indexed project_paths

  local selected_index=$(verified_read "Select project: " "[0-9]+")
  eval "$1=${project_ids[$((selected_index - 1))]}"
}

api_fill_branch_name() {
  local project_id=$1
  eval "$2=''"

  echo "Getting branches..."
  local branches=()
  local api_url=$(get_file_value "$config_path" "api_url" 2)
  local token=$(get_file_value "$config_path" "token" 2)
  local json=$(curl -s --request GET "$api_url/projects/$project_id/repository/branches?access_token=$token")
  branches=($(echo $json | awk -F '[:,]' '{for(i=1;i<=NF;i++){if($i ~ /"name"/){gsub(/[[:space:]]|"|/,"",$(i+1)); print $(i+1)}}}'))
  if [ ${#branches[@]} -eq 0 ]; then
    echo "No branches found" >&2
    return
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

  if [ ${#jobs[@]} -eq 0 ]; then
    echo "No jobs found" >&2
    return
  fi

  print_array_indexed jobs

  local selected_index=$(verified_read "Select job: " "[0-9]+")
  eval "$3=${jobs[$((selected_index - 1))]}"
}

############################################
# Функции взаимодействия с пользователем
############################################

user_api_modification() {
  # Используем verified_read для валидации ввода regex'ом
  local action=$(verified_read "Choose action (edit [u]rl / edit [t]oken / [p]rint): " "[u|t|p]")
  case $action in
  u | U)
    user_edit_api_url
    ;;
  t | T)
    user_edit_token
    ;;
  p | P)
    echo "API URL: $(get_file_value "$config_path" "api_url" 2)"
    echo "Token: $(get_file_value "$config_path" "token" 2)"
    ;;
  esac
}

user_edit_api_url() {
  local new_api_url=$(verified_read "Enter new API URL: " "^[^[:space:]]+$")
  edit_file_value "$config_path" "api_url" 2 "$new_api_url"
  local test=$(curl -sf --request GET "$new_api_url/projects?simple=true&min_access_level=20")
  if [[ $? -ne 0 || $test != "[]" ]]; then
    echo "API URL is invalid" >&2
  fi
  echo "API URL changed successfully"
}

user_edit_token() {
  local new_token=$(verified_read "Enter new token: " "^[^[:space:]]+$")
  edit_file_value "$config_path" "token" 2 "$new_token"
  local test=$(curl -sf --request GET "$new_api_url/projects?simple=true&min_access_level=20&access_token=$new_token")
  if [[ $? -ne 0 || $test == "[]" ]]; then
    echo "Token is invalid" >&2
  fi
  echo "Token changed successfully"
}

user_switch_scenario_file() {
  scenario_path=$(verified_read "Enter new scenario file: " "^[^[:space:]]+$")
  touch "$scenario_path"
}


user_hosts_modification() {
  local action=$(verified_read "Choose action ([a]dd / [e]dit / [d]elete / [p]rint): " "[a|e|d|p]")
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
  esac
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
  local options=("1) Name" "2) IP" "3) Port" "4) Username" "5) Password")
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
  local headers=()
  print_table "$hosts_path" "Name" "IP" "Port" "Username" "Password"
}


user_artifacts_modification() {
  local action=$(verified_read "Choose action ([a]dd / [e]dit / [c]opy / [d]elete / [p]rint): " "[a|e|c|d|p]")
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
  esac
}

user_add_artifact() {
  local project_id
  api_fill_project_id project_id
  if [ $project_id -eq 0 ]; then
    echo "No projects found" >&2
    return
  fi

  local branch_name
  api_fill_branch_name $project_id branch_name
  if [ -z $branch_name ]; then
    echo "No branches found" >&2
    return
  fi
  local job_name
  api_fill_job_name $project_id $branch_name job_name
  if [ -z $job_name ]; then
    echo "No jobs found" >&2
    return
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
  local options=("1) Name" "2) Project ID" "3) Branch" "4) Job" "5) Files")
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
  local action=$(verified_read "Choose action ([a]dd / [d]elete / [p]rint): " "[a|d|p]")
  case $action in
  a | A)
    user_add_scenario_pair
    ;;
  d | D)
    user_delete_scenario_pair
    ;;
  p | P)
    user_print_scenario_info
    ;;
  esac
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
  echo "2) Switch scenario file"
  echo "3) Hosts modification"
  echo "4) Artifacts modification"
  echo "5) Scenario modification"
  echo "c) Clear cache"
  echo "d) Deploy"
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
      user_switch_scenario_file
      ;;
    3)
      user_hosts_modification
      ;;
    4)
      user_artifacts_modification
      ;;
    5)
      user_scenario_modification
      ;;
    c | C)
      rm -rf cache
      ;;
    d | D)
      main_deploy
      ;;
    q | Q)
      break
      ;;
    *)
      echo "Invalid option" >&2
      ;;
    esac
  done
}

main_deploy() {
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
    # Если кэша для этого артефакта нет, то скачиваем
    if [[ ! -d "cache/$artifact_name" ]]; then
      mkdir -p cache/$artifact_name
      cd cache/$artifact_name
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
          curl --location --output "$file" --request GET "$api_url/projects/$artifact_project_id/jobs/artifacts/$artifact_branch_name/raw/$file?job=$artifact_job_name&access_token=$token"
        done
      fi
      cd ../..
    fi
    # Непосредственно деплой
    echo "Deploying to $machine_name($machine_path)"
    # Путь на локальной машине считается относительно ДИРЕКТОРИИ ПОЛЬЗОВАТЕЛЯ
    if [[ $machine_name == "Local" ]]; then
      if [[ $machine_path != /* ]]; then
        machine_path="$HOME/$machine_path"
      fi
      cp -r cache/$artifact_name/* $machine_path
    # Если пароль не указан, подразумеваем что есть беспрепятственный доступ по ключу
    # и используем scp
    elif [[ $machine_password == "-" ]]; then
      scp -P $machine_port -r cache/$artifact_name/* $machine_username@$machine_ip:$machine_path
    # Иначе используем sftp с sshpass
    else
      SSHPASS=$machine_password sshpass -e sftp -P $machine_port -oBatchMode=no -b - "$machine_username@$machine_ip" <<EOF
lcd cache/$artifact_name
cd $directory
put -r *
bye
EOF
    fi
  done <"$scenario_path"
}

artifacts_path=".artifacts"
config_path=".deployconfig"
hosts_path=".hosts"
scenario_path="main.dsc"
edit_mode=true

# Парсинг аргументов командной строки
while [[ $# -gt 0 ]]; do
  case "$1" in
  # -a или --artifacts
  -a | --artifacts)
    artifacts_path="$2"
    echo "Artifacts path: $artifacts_path"
    shift 2
    ;;
  -h | --hosts)
    hosts_path="$2"
    echo "Hosts path: $hosts_path"
    shift 2
    ;;
  -c | --config)
    config_path="$2"
    echo "Config path: $config_path"
    shift 2
    ;;
  -s | --scenario)
    scenario_path="$2"
    echo "Scenario path: $scenario_path"
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

touch "$artifacts_path"
touch "$hosts_path"
touch "$scenario_path"

if [[ ! -f "$config_path" ]]; then
  touch "$config_path"
  echo -e "api_url\t-" >>"$config_path"
  echo -e 'token\t-' >>"$config_path"
fi

if [ "$edit_mode" = true ]; then
  main_edit
else
  main_deploy
fi
