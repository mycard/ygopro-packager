FROM node

WORKDIR /usr/src/app
COPY package.json /usr/src/app
COPY package-lock.json /usr/src/app
RUN npm install

CMD curl --location --retry 5 --output ossutil "http://ossutil-version-update.oss-cn-hangzhou.aliyuncs.com/$(curl http://ossutil-version-update.oss-cn-hangzhou.aliyuncs.com/ossutilversion)/ossutil64"
CMD chmod +x ossutil

COPY . /usr/src/app
ENTRYPOINT npm start