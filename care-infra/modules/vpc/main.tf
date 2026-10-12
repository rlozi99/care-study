variable "project_name" {}
variable "vpc_cidr" {               // variable-> 테라폼에서 정해놓은 예약어. 지금부터 입력 변수를 하나 선언하겠다고 테라폼에게 알려주는 신호
                                    // "vpc_cidr" -> 내가 이 변수에게 붙이는 이름. 다른 이름으로 바꿔도 문제없다.
  default = "10.0.0.0/16"           // 이 변수에 값을 안주면 이걸 쓰겠다는 의미 
  type    = string                  //큰 따옴표로 감싸져 있으므로 string 타입이다 
  description = "VPC의 IP 대역"     // IP대역 = 사용 가능한 IP 주소들의 묶음. 
  } 

/*
10.0.0.0/16
   ↑     ↑
시작주소|대역의 크기(몇 개의 IP를 포함하는지)

- IP 주소는 32비트로 구성되어 있다.
  - 0000.0000.0000.0000 -> 숫자 하나당 2비트니까 16*2=32비트
  - /16 -> 앞 16비트는 고정, 뒤 16비트는 자유롭게 바뀔 수 있다
*/

/*
10.0.0.0/16
= 앞 비트(10.0) 고정
= 뒤 비트(0.0) 0~65535까지 다 가능 -> 2^16 = 65536
= 즉, 10.0.0.0 ~ 10.0.255.255 까지 모든 IP를 포함 (총 65536개)
*/

/*
* 대역이 왜 필요한가?
- vpc를 만들 때, 여기서부터 여기까지의 IP는 이 네트워크 안에서만 쓸게 라고 미리 영역을 그어놓는 것이 목적이다.
  - 그래야 그 안에서 서브넷(작은 구역)들을 잘라서 나눠 쓸 수 있다.

전체 대역: 10.0.0.0/16 (65536개, 아파트 단지 전체)
  └── 서브넷1: 10.0.1.0/24 (256개, 그중 한 개 동)
  └── 서브넷2: 10.0.2.0/24 (256개, 또 다른 한 개 동)
*/

variable "azs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }

/*
resource "타입" "이름" {
  설정...
}

1. resource(키워드): 지금부터 AWS에 실제 리소스 하나 만들겠다는 선언
2. 타입: 리소스 타입. "무엇을 만들지"에 해당하는 부분으로, AWS/Terraform이 정해놓은 정확한 이름을 그대로 써야함. ex) aws_vpc..
3. 이름: 이 리소스에 붙이는 별명(로컬 이름). 내가 자유롭게 짓는 이름
    - 나중에 이 리소스를 다른 곳에서 참조할 때, aws_vpc.main.id 이런 식으로 쓰기 위한 식별자
*/

/*
설정 안에 들어가는 것 = 속성
속성은 무언가를 가리키는 역할

cidr_block = var.vpc_cidr
- 가리키는 것: 이 VPC가 사용할 전체 IP 주소 범위
enable_dns_hostnames = true
- 가리키는 것: VPC 안의 인스턴스(EC2, EKS 노드 등)에 DNS 호스트 네임을 자동으로 부여할지 여부
enable_dns_support = true
- 가리키는 것: VPC 안에서 AWS내부 DNS 조회 기능 자체를 켤지 여부
tag = { Name = "${var.project_name}-vpc"}
- 가리키는 것: 이 VPC 리소스에 붙이는 이름표(메타데이터)
*/
resource "aws_vpc" "main" {             // "resource를 만든다. 타입은 aws_vpc 즉 VPC이고, 내가 붙일 이름은 main이다. 세부 설정은 중괄호 안에 적겠다."
  cidr_block           = var.vpc_cidr   // var = variable 블록을 참조하겠다. 거기에 있는 vpc_cidr 설명들을 참조한다.
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id              // aws_vpc 타입의 main을 참조할것이고 거기에 있는 id 값을 참조할 것이다.

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }